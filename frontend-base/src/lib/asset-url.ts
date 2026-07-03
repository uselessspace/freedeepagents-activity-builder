/**
 * Normalize asset URLs (sprite images, file uploads, etc.) so they resolve
 * correctly under the dev server, direct FDA preview mounts, and the Go
 * developer preview proxy.
 */

import { BASE_PREFIX } from './api-base';

type PreviewMount = {
  activityTypeId: string;
  activityId: string;
  prefix: string;
};

type StoredPreviewUpload = {
  activityTypeId: string;
  activityId: string;
  rest: string;
};

function parseCurrentPreviewMount(prefix: string): PreviewMount | null {
  const parts = prefix.split('/').filter(Boolean);
  const previewIdx = parts.indexOf('preview');
  if (previewIdx < 0) return null;

  const isGoDeveloperPreviewMount =
    previewIdx >= 7 &&
    parts[0] === 'api' &&
    parts[1] === 'v1' &&
    parts[2] === 'developer' &&
    parts[3] === 'activity-types' &&
    parts[5] === 'activities' &&
    parts[7] === 'preview';
  if (isGoDeveloperPreviewMount) {
    return {
      activityTypeId: parts[4],
      activityId: parts[6],
      prefix: `/${parts.slice(0, previewIdx + 1).join('/')}`,
    };
  }

  if (parts.length >= previewIdx + 3) {
    return {
      activityTypeId: parts[previewIdx + 1],
      activityId: parts[previewIdx + 2],
      prefix: `/${parts.slice(0, previewIdx + 3).join('/')}`,
    };
  }
  return null;
}

function parseStoredPreviewUpload(src: string): StoredPreviewUpload | null {
  const parts = src.split('/').filter(Boolean);
  const previewIdx = parts.indexOf('preview');
  if (previewIdx < 0 || parts.length < previewIdx + 4 || parts[previewIdx + 3] !== 'uploads') {
    return null;
  }
  return {
    activityTypeId: parts[previewIdx + 1],
    activityId: parts[previewIdx + 2],
    rest: parts.slice(previewIdx + 3).join('/'),
  };
}

function rewritePreviewPathForCurrentProxy(src: string): string | null {
  if (!src.startsWith('/preview/') && !src.startsWith('/dev/preview/')) return null;

  const mount = parseCurrentPreviewMount(BASE_PREFIX);
  const upload = parseStoredPreviewUpload(src);
  if (!mount || !upload) return null;
  if (mount.activityTypeId !== upload.activityTypeId || mount.activityId !== upload.activityId) {
    return null;
  }
  return `${mount.prefix}/${upload.rest}`;
}

export function resolveAssetUrl(src: string): string {
  if (!src) return src;
  if (/^(https?:|data:|blob:)/i.test(src)) return src;
  const proxiedPreviewPath = rewritePreviewPathForCurrentProxy(src);
  if (proxiedPreviewPath) return proxiedPreviewPath;
  if (BASE_PREFIX && src.startsWith(BASE_PREFIX + '/')) return src;
  if (src.startsWith('/')) return BASE_PREFIX + src;
  return src;
}
