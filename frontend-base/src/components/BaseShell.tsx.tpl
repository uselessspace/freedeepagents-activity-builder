import type { ReactNode } from 'react';

interface Props {
  title: string;
  children: ReactNode;
  rightSlot?: ReactNode;
}

export function BaseShell({ title, children, rightSlot }: Props) {
  return (
    <div style={{ minHeight: '100vh', display: 'flex', flexDirection: 'column' }}>
      <header
        style={{
          display: 'flex',
          alignItems: 'center',
          padding: '12px 20px',
          background: '#fff',
          borderBottom: '1px solid #e2e8f0',
          gap: 12,
        }}
      >
        <div
          aria-hidden
          style={{
            width: 12,
            height: 12,
            borderRadius: 4,
            background: '{{ACCENT_COLOR}}',
          }}
        />
        <strong style={{ fontSize: 14 }}>{title}</strong>
        <div style={{ marginLeft: 'auto' }}>{rightSlot}</div>
      </header>
      <main style={{ flex: 1, overflow: 'auto' }}>{children}</main>
    </div>
  );
}
