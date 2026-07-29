import { z } from 'zod';

/**
 * @openapi
 * components:
 *   schemas:
 *     TimetableClass:
 *       type: object
 *       properties:
 *         day:
 *           type: string
 *           enum: [MON, TUE, WED, THU, FRI, SAT, SUN]
 *         startTime:
 *           type: string
 *         endTime:
 *           type: string
 *         room:
 *           type: string
 *           nullable: true
 *         type:
 *           type: string
 *           enum: [CORE, LAB, BREAK]
 *     TimetableSubject:
 *       type: object
 *       properties:
 *         id:
 *           type: string
 *         name:
 *           type: string
 *         code:
 *           type: string
 *         classes:
 *           type: array
 *           items:
 *             $ref: '#/components/schemas/TimetableClass'
 *     Timetable:
 *       type: object
 *       properties:
 *         subjects:
 *           type: array
 *           items:
 *             $ref: '#/components/schemas/TimetableSubject'
 */

export const TimetableClassSchema = z.object({
  day: z.enum(['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN']),
  startTime: z.string(),
  endTime: z.string(),
  room: z.string().optional(),
  type: z.enum(['CORE', 'LAB', 'BREAK']),
});

export const TimetableSubjectSchema = z.object({
  id: z.string(),
  name: z.string(),
  code: z.string(),
  classes: z.array(TimetableClassSchema),
});

export const TimetableSchema = z.object({
  subjects: z.array(TimetableSubjectSchema),
});

export type Timetable = z.infer<typeof TimetableSchema>;
