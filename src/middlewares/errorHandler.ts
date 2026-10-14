import type { Request, Response, NextFunction } from 'express';

/** Error API terstruktur dengan status HTTP. */
export class ApiError extends Error {
  status: number;
  details?: unknown;

  constructor(status: number, message: string, details?: unknown) {
    super(message);
    this.status = status;
    this.details = details;
  }

  static badRequest(msg: string, details?: unknown): ApiError {
    return new ApiError(400, msg, details);
  }

  static notFound(msg: string, details?: unknown): ApiError {
    return new ApiError(404, msg, details);
  }

  static upstream(msg: string, details?: unknown): ApiError {
    return new ApiError(502, msg, details);
  }
}

/** Bungkus controller async agar error diteruskan ke middleware. */
export const asyncHandler =
  (fn: (req: Request, res: Response, next: NextFunction) => Promise<unknown>) =>
  (req: Request, res: Response, next: NextFunction): void => {
    fn(req, res, next).catch(next);
  };

/** Middleware error global — selalu kembalikan JSON konsisten. */
export function errorMiddleware(
  err: unknown,
  _req: Request,
  res: Response,
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  _next: NextFunction,
): void {
  const status = err instanceof ApiError ? err.status : 500;
  const message = err instanceof Error ? err.message : 'Internal server error';
  if (status === 500) {
    console.error('[projectnext]', err);
  }
  res.status(status).json({
    success: false,
    status,
    message,
    ...(err instanceof ApiError && err.details !== undefined ? { details: err.details } : {}),
  });
}

/** 404 untuk route tak dikenal. */
export function notFoundMiddleware(_req: Request, res: Response): void {
  res.status(404).json({ success: false, status: 404, message: 'Route not found' });
}
