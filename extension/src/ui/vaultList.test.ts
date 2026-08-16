import { describe, expect, it } from 'vitest';
import { filterEntries } from './vaultList';
import type { VaultEntry } from '../session/sessionState';

function entry(overrides: Partial<VaultEntry>): VaultEntry {
  return {
    id: 'id-1',
    site: 'example.com',
    url: '',
    username: 'alice',
    password: 'hunter2',
    notes: '',
    profiles: [],
    ...overrides,
  };
}

describe('filterEntries', () => {
  const entries = [
    entry({ id: '1', site: 'github.com', username: 'octocat' }),
    entry({ id: '2', site: 'gitlab.com', username: 'alice' }),
    entry({ id: '3', site: '', url: 'https://weird-host.example', username: 'bob' }),
  ];

  it('returns every entry when the query is empty', () => {
    expect(filterEntries(entries, '')).toEqual(entries);
    expect(filterEntries(entries, '   ')).toEqual(entries);
  });

  it('matches by site substring, case-insensitive', () => {
    expect(filterEntries(entries, 'GIT')).toEqual([entries[0], entries[1]]);
    expect(filterEntries(entries, 'hub')).toEqual([entries[0]]);
  });

  it('matches by username substring, case-insensitive', () => {
    expect(filterEntries(entries, 'OCTO')).toEqual([entries[0]]);
  });

  it('falls back to url when site is empty', () => {
    expect(filterEntries(entries, 'weird-host')).toEqual([entries[2]]);
  });

  it('returns an empty array when nothing matches', () => {
    expect(filterEntries(entries, 'nonexistent')).toEqual([]);
  });
});
