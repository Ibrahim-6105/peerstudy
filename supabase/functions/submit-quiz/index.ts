// Score one saved ten-question quiz on the server and persist one Attempt.

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
  scoreAnswers,
  validateAnswers,
  validatePrivateQuestions,
} from "../_shared/quiz.ts";

// Never return the Student's auth/profile row or the full private quiz object.
function attemptPayload(
  row: Record<string, unknown>,
  alreadySubmitted: boolean,
) {
  return {
    attempt_id: row.id,
    quiz_id: row.quiz_id,
    subject_id: row.subject_id,
    score: row.score,
    total: row.total,
    corrections: row.corrections,
    completed_at: row.completed_at,
    already_submitted: alreadySubmitted,
  };
}

// A replay is valid only when its ten choices are byte-for-byte equivalent.
function sameAnswers(stored: unknown, supplied: number[]): boolean {
  return Array.isArray(stored) && stored.length === supplied.length &&
    stored.every((answer, index) => answer === supplied[index]);
}

Deno.serve(async (request) => {
  const correlationId = requestId(request);
  try {
    const preflight = preflightResponse(request);
    if (preflight) return preflight;

    const { service, user } = await authenticate(request);
    await requireActiveStudent(service, user.id);
    const body = await readJsonObject(request);
    const quizId = requireUuid(body.quiz_id, "quiz_id");
    const idempotencyKey = requireUuid(body.idempotency_key, "idempotency_key");
    const answers = validateAnswers(body.answers);

    // Correct answers are fetched with the service role and never accepted from
    // or exposed to the phone until scoring has finished.
    const { data: quiz, error: quizError } = await service
      .from("quizzes")
      .select("id, subject_id, material_id, created_by, questions, status")
      .eq("id", quizId)
      .maybeSingle();
    if (quizError) {
      throw new ApiError(
        503,
        "The Quiz could not be loaded.",
        "database-unavailable",
      );
    }
    if (!quiz || quiz.created_by !== user.id || quiz.status !== "ready") {
      throw new ApiError(404, "The Quiz is unavailable.", "quiz-unavailable");
    }
    if (
      typeof quiz.subject_id !== "string" ||
      typeof quiz.material_id !== "string"
    ) {
      throw new ApiError(
        409,
        "This Quiz was retired because its source PDF is no longer available.",
        "quiz-retired",
      );
    }
    const quizSubjectId = requireUuid(quiz.subject_id, "quiz.subject_id");
    const quizMaterialId = requireUuid(quiz.material_id, "quiz.material_id");
    await requireActiveSubject(service, quizSubjectId);

    const { data: material, error: materialError } = await service
      .from("subject_materials")
      .select("id, status")
      .eq("id", quizMaterialId)
      .maybeSingle();
    if (materialError || !material || material.status !== "approved") {
      throw new ApiError(
        409,
        "The Quiz source material is no longer approved.",
        "material-unavailable",
      );
    }
    const questions = validatePrivateQuestions(quiz.questions);

    // The same idempotency key can safely recover a lost successful response.
    const { data: byRequest, error: byRequestError } = await service
      .from("quiz_attempts")
      .select(
        "id, quiz_id, subject_id, answers, score, total, corrections, completed_at",
      )
      .eq("student_id", user.id)
      .eq("idempotency_key", idempotencyKey)
      .maybeSingle();
    if (byRequestError) {
      throw new ApiError(
        503,
        "Attempt state could not be checked.",
        "database-unavailable",
      );
    }
    if (byRequest) {
      if (
        byRequest.quiz_id !== quizId || !sameAnswers(byRequest.answers, answers)
      ) {
        throw new ApiError(
          409,
          "idempotency_key was used for another submission.",
          "idempotency-conflict",
        );
      }
      return jsonResponse(request, attemptPayload(byRequest, true), 200);
    }

    // Each generated Quiz has one final Attempt for its Student creator.
    const { data: byQuiz, error: byQuizError } = await service
      .from("quiz_attempts")
      .select(
        "id, quiz_id, subject_id, answers, score, total, corrections, completed_at",
      )
      .eq("student_id", user.id)
      .eq("quiz_id", quizId)
      .maybeSingle();
    if (byQuizError) {
      throw new ApiError(
        503,
        "Attempt state could not be checked.",
        "database-unavailable",
      );
    }
    if (byQuiz) {
      if (!sameAnswers(byQuiz.answers, answers)) {
        throw new ApiError(
          409,
          "This Quiz already has a different final submission.",
          "quiz-already-submitted",
        );
      }
      return jsonResponse(request, attemptPayload(byQuiz, true), 200);
    }

    const scored = scoreAnswers(questions, answers);
    const completedAt = new Date().toISOString();
    const { data: inserted, error: insertError } = await service
      .from("quiz_attempts")
      .insert({
        quiz_id: quizId,
        subject_id: quizSubjectId,
        student_id: user.id,
        answers,
        score: scored.score,
        total: 10,
        corrections: scored.corrections,
        status: "submitted",
        idempotency_key: idempotencyKey,
        started_at: completedAt,
        completed_at: completedAt,
      })
      .select(
        "id, quiz_id, subject_id, answers, score, total, corrections, completed_at",
      )
      .single();
    if (!insertError && inserted) {
      return jsonResponse(request, attemptPayload(inserted, false), 201);
    }
    if (insertError?.code !== "23505") {
      throw new ApiError(
        503,
        "The Attempt could not be saved.",
        "attempt-save-failed",
      );
    }

    // Concurrent duplicate submissions converge on the one saved Attempt.
    const { data: raced, error: racedError } = await service
      .from("quiz_attempts")
      .select(
        "id, quiz_id, subject_id, answers, score, total, corrections, completed_at",
      )
      .eq("student_id", user.id)
      .eq("quiz_id", quizId)
      .maybeSingle();
    if (racedError || !raced || !sameAnswers(raced.answers, answers)) {
      throw new ApiError(
        409,
        "This Quiz was submitted by another request.",
        "quiz-already-submitted",
      );
    }
    return jsonResponse(request, attemptPayload(raced, true), 200);
  } catch (error) {
    return errorResponse(request, error, correlationId);
  }
});
