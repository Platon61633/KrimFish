import { ZodError } from 'zod';
import { HttpError } from './errors.js';

/**
 * validate({ params, query, body }) проверяет запрос схемами zod
 * и кладёт результат в req.valid.{params,query,body}.
 */
export const validate = (schemas) => (req, _res, next) => {
  try {
    req.valid = {};
    for (const part of ['params', 'query', 'body']) {
      if (schemas[part]) req.valid[part] = schemas[part].parse(req[part] ?? {});
    }
    next();
  } catch (err) {
    if (err instanceof ZodError) {
      const details = err.issues.map((i) => ({ path: i.path.join('.'), message: i.message }));
      return next(new HttpError(400, 'Некорректные данные запроса', details));
    }
    next(err);
  }
};
