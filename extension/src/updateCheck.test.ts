import { afterEach, describe, expect, it, vi } from 'vitest';
import { checkForUpdate, isNewer } from './updateCheck';

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('isNewer', () => {
  it('detects a newer major/minor/patch', () => {
    expect(isNewer('2.0.0', '1.0.0')).toBe(true);
    expect(isNewer('1.1.0', '1.0.0')).toBe(true);
    expect(isNewer('1.0.1', '1.0.0')).toBe(true);
  });

  it('is false when equal or older', () => {
    expect(isNewer('1.0.0', '1.0.0')).toBe(false);
    expect(isNewer('1.0.0', '2.0.0')).toBe(false);
  });
});

describe('checkForUpdate', () => {
  it('returns the tag when the release is newer', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => new Response(JSON.stringify({ tag_name: 'v2.0.0' }), { status: 200 })),
    );
    expect(await checkForUpdate('1.0.0')).toBe('2.0.0');
  });

  it('returns null when already on the latest release', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => new Response(JSON.stringify({ tag_name: 'v2.0.0' }), { status: 200 })),
    );
    expect(await checkForUpdate('2.0.0')).toBeNull();
  });

  it('returns null when the request fails', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => {
        throw new Error('network down');
      }),
    );
    expect(await checkForUpdate('1.0.0')).toBeNull();
  });

  it('returns null when the response has no tag_name', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => new Response(JSON.stringify({}), { status: 200 })),
    );
    expect(await checkForUpdate('1.0.0')).toBeNull();
  });
});
