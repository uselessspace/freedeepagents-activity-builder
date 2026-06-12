import { ApiErrorBanner } from './components/ApiErrorBanner';
import { BaseShell } from './components/BaseShell';
import { LoadingSpinner } from './components/LoadingSpinner';
import { useDsl } from './hooks/useDsl';

function DomainView() {
  const { data, error, loading, refresh } = useDsl();

  if (loading) {
    return (
      <div className="flex min-h-[320px] items-center justify-center">
        <LoadingSpinner label="Loading preview" />
      </div>
    );
  }

  return (
    <div className="mx-auto flex w-full max-w-5xl flex-col gap-5 p-6">
      {error ? <ApiErrorBanner error={error} onRetry={refresh} /> : null}
      <section className="rounded-lg border border-slate-200 bg-white p-5 shadow-sm">
        <p className="text-sm font-medium text-slate-500">{{ACTIVITY_NAME}}</p>
        <h1 className="mt-2 text-2xl font-semibold text-slate-950">
          {data?.title ?? '{{ACTIVITY_NAME}}'}
        </h1>
        {typeof data?.summary === 'string' ? (
          <p className="mt-3 text-sm leading-6 text-slate-700">{data.summary}</p>
        ) : null}
      </section>

      <section className="grid gap-3 sm:grid-cols-2">
        {(data?.items ?? []).map((item) => (
          <article key={item.id} className="rounded-lg border border-slate-200 bg-white p-4">
            <h2 className="text-sm font-semibold text-slate-950">{item.label}</h2>
            {item.value ? <p className="mt-2 text-sm text-slate-600">{item.value}</p> : null}
          </article>
        ))}
      </section>
    </div>
  );
}

export default function App() {
  return (
    <BaseShell title="{{ACTIVITY_NAME}}">
      <DomainView />
    </BaseShell>
  );
}
