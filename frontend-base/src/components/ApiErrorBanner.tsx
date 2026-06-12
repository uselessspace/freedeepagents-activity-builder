interface Props {
  error: Error | null;
  onRetry?: () => void;
}

export function ApiErrorBanner({ error, onRetry }: Props) {
  if (!error) return null;
  return (
    <div
      role="alert"
      style={{
        background: '#fef2f2',
        borderBottom: '1px solid #fecaca',
        color: '#7f1d1d',
        padding: '8px 16px',
        fontSize: 13,
        display: 'flex',
        alignItems: 'center',
        gap: 12,
      }}
    >
      <span style={{ flex: 1 }}>{error.message}</span>
      {onRetry ? (
        <button
          onClick={onRetry}
          style={{
            background: '#fff',
            border: '1px solid #fca5a5',
            color: '#7f1d1d',
            padding: '4px 10px',
            borderRadius: 4,
            cursor: 'pointer',
          }}
        >
          Retry
        </button>
      ) : null}
    </div>
  );
}
