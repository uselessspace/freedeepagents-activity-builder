/**
 * Activity-specific TypeScript types.
 *
 * Keep `AppDsl` aligned with the dict returned by
 * activities/{{ACTIVITY_ID}}/dsl_builder.py.
 */

export interface AppDsl {
  title?: string;
  summary?: string;
  items?: Array<{
    id: string;
    label: string;
    value?: string;
  }>;
  updated_at?: string;
  [key: string]: unknown;
}
