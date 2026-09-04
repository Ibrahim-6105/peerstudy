// Generate exactly ten private-answer questions from one approved Subject PDF.

import {
  ApiError,
  authenticate,
  errorResponse,
  jsonResponse,
  preflightResponse,
  readJsonObject,
  requestId,
  requireActiveStudent,
  requireActiveSubject,
  requireUuid,
} from "../_shared/http.ts";
import {
  generateQuestionsFromPdf,
  type PrivateQuizQuestion,
  publicQuestions,
  sha256Hex,
  validatePrivateQuestions,
} from "../_shared/quiz.ts";

// Only these public fields are returned before the Student submits answers.
function quizPayload(row: Record<string, unknown>) {
  const questions = validatePrivateQuestions(row.questions);
  return {
    quiz_id: row.id,
    subject_id: row.subject_id,
    material_id: row.material_id,
    title: row.title,
    total: 10,
    questions: publicQuestions(questions),
  };
}

Deno.serve(async (request) => {
  const correlationId = requestId(request);
  try {
    const preflight = preflightResponse(request);
    if (preflight) return preflight;

    const { service, user } = await authenticate(request);
    await requireActiveStudent(service, user.id);
    const body = await readJsonObject(request);
    const subjectId = requireUuid(body.subject_id, "subject_id");
    const materialId = requireUuid(body.material_id, "material_id");
    const idempotencyKey = requireUuid(body.idempotency_key, "idempotency_key");

    // Replaying the same completed request is cheap and never calls AI twice.
    const { data: existing, error: existingError } = await service
      .from("quizzes")
      .select("id, subject_id, material_id, title, questions, status")
      .eq("created_by", user.id)
      .eq("idempotency_key", idempotencyKey)
      .maybeSingle();
    if (existingError) {
      throw new ApiError(
        503,
        "Existing quiz state could not be checked.",
        "database-unavailable",
      );
    }
    if (existing) {
      if (existing.status !== "ready") {
        throw new ApiError(
          409,
          "This Quiz was retired because its source PDF is no longer available.",
          "quiz-retired",
        );
      }
      if (
        existing.subject_id !== subjectId || existing.material_id !== materialId
      ) {
        throw new ApiError(
          409,
          "idempotency_key was used for another quiz request.",
          "idempotency-conflict",
        );
      }
    }

    // Validate the live Subject and PDF even for an idempotent replay. A
    // previously generated Quiz may have been retired and detached by an
    // Admin's permanent catalog deletion.
    await requireActiveSubject(service, subjectId);
    const { data: material, error: materialError } = await service
      .from("subject_materials")
      .select(
        "id, subject_id, title, storage_path, mime_type, size_bytes, checksum, status",
      )
      .eq("id", materialId)
      .maybeSingle();
    if (materialError) {
      throw new ApiError(
        503,
        "The Material could not be verified.",
        "material-check-failed",
      );
    }

    if (
      !material || material.subject_id !== subjectId ||
      material.status !== "approved" ||
      material.mime_type !== "application/pdf" ||
      typeof material.checksum !== "string"
    ) {
      throw new ApiError(
        404,
        "The approved PDF is unavailable.",
        "material-unavailable",
      );
    }

    if (existing) {
      return jsonResponse(request, quizPayload(existing), 200);
    }

    // Limit completed generations per Student. Idempotent replay was checked
    // first so a lost response does not consume another allowance.
    const configuredLimit = Number(
      Deno.env.get("QUIZ_GENERATION_PER_MINUTE") ?? "3",
    );
    const perMinuteLimit = Number.isInteger(configuredLimit)
      ? Math.min(Math.max(configuredLimit, 1), 20)
      : 3;
    const oneMinuteAgo = new Date(Date.now() - 60_000).toISOString();
    const { count, error: countError } = await service
      .from("quizzes")
      .select("id", { count: "exact", head: true })
      .eq("created_by", user.id)
      .gte("created_at", oneMinuteAgo);
    if (countError) {
      throw new ApiError(
        503,
        "Quiz usage could not be checked.",
        "database-unavailable",
      );
    }
    if ((count ?? 0) >= perMinuteLimit) {
      throw new ApiError(
        429,
        "Please wait before generating another quiz.",
        "quiz-rate-limited",
      );
    }

    // Storage is private; only this authenticated server path downloads bytes.
    const { data: pdfBlob, error: downloadError } = await service.storage
      .from("subject-materials")
      .download(material.storage_path);
    if (downloadError || !pdfBlob) {
      throw new ApiError(
        503,
        "The approved PDF could not be downloaded.",
        "material-download-failed",
      );
    }
    const pdfBytes = new Uint8Array(await pdfBlob.arrayBuffer());
    const recordedSize = Number(material.size_bytes);
    if (
      pdfBytes.byteLength < 1 || pdfBytes.byteLength > 26_214_400 ||
      !Number.isSafeInteger(recordedSize) ||
      recordedSize !== pdfBytes.byteLength
    ) {
      throw new ApiError(
        409,
        "The approved PDF size does not match its record.",
        "material-integrity-failed",
      );
    }
    const header = new TextDecoder("ascii").decode(pdfBytes.subarray(0, 1024));
    if (!header.includes("%PDF-")) {
      throw new ApiError(
        409,
        "The approved file is not a valid PDF.",
        "material-integrity-failed",
      );
    }
    if (await sha256Hex(pdfBytes) !== material.checksum.toLowerCase()) {
      throw new ApiError(
        409,
        "The approved PDF checksum does not match.",
        "material-integrity-failed",
      );
    }

    const generated = await generateQuestionsFromPdf(
      pdfBytes,
      material.title,
      correlationId,
    );
    const title = `Quiz - ${material.title}`.slice(0, 240);
    const insertPayload = {
      subject_id: subjectId,
      material_id: materialId,
      created_by: user.id,
      title,
      questions: generated.questions as PrivateQuizQuestion[],
      status: "ready",
      model_name: generated.model,
      idempotency_key: idempotencyKey,
    };
    const { data: inserted, error: insertError } = await service
      .from("quizzes")
      .insert(insertPayload)
      .select("id, subject_id, material_id, title, questions, status")
      .single();

    if (!insertError && inserted) {
      return jsonResponse(request, quizPayload(inserted), 201);
    }
    if (insertError?.code !== "23505") {
      throw new ApiError(
        503,
        "The generated quiz could not be saved.",
        "quiz-save-failed",
      );
    }

    // A concurrent request with the same key may win the unique constraint.
    const { data: raced, error: racedError } = await service
      .from("quizzes")
      .select("id, subject_id, material_id, title, questions, status")
      .eq("created_by", user.id)
      .eq("idempotency_key", idempotencyKey)
      .maybeSingle();
    if (racedError || !raced) {
      throw new ApiError(
        409,
        "idempotency_key conflicts with another request.",
        "idempotency-conflict",
      );
    }
    if (raced.status !== "ready") {
      throw new ApiError(
        409,
        "This Quiz was retired because its source PDF is no longer available.",
        "quiz-retired",
      );
    }
    if (
      raced.subject_id !== subjectId || raced.material_id !== materialId
    ) {
      throw new ApiError(
        409,
        "idempotency_key conflicts with another request.",
        "idempotency-conflict",
      );
    }
    return jsonResponse(request, quizPayload(raced), 200);
  } catch (error) {
    return errorResponse(request, error, correlationId);
  }
});
