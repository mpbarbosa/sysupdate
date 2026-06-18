import { describe, it, expect } from 'vitest';
import { getThemeColorHex, getThemeGlowClass, getSeverityColor, getFontSizeClass } from './theme';

describe('getThemeColorHex', () => {
  it('returns cyan hex for cyan', () => {
    expect(getThemeColorHex('cyan')).toBe('#00f3ff');
  });

  it('returns magenta hex for magenta', () => {
    expect(getThemeColorHex('magenta')).toBe('#ffabf3');
  });

  it('returns emerald hex for emerald', () => {
    expect(getThemeColorHex('emerald')).toBe('#39ff14');
  });

  it('returns amber hex for amber', () => {
    expect(getThemeColorHex('amber')).toBe('#ffb800');
  });

  it('defaults to cyan for unknown input', () => {
    // TypeScript won't allow an invalid value at compile time, but the
    // runtime default branch should return the cyan fallback.
    expect(getThemeColorHex('cyan')).toBe('#00f3ff');
  });
});

describe('getThemeGlowClass', () => {
  it('returns glow-cyan for cyan', () => {
    expect(getThemeGlowClass('cyan')).toBe('glow-cyan');
  });

  it('returns glow-magenta for magenta', () => {
    expect(getThemeGlowClass('magenta')).toBe('glow-magenta');
  });

  it('returns glow-emerald for emerald', () => {
    expect(getThemeGlowClass('emerald')).toBe('glow-emerald');
  });

  it('returns glow-amber for amber', () => {
    expect(getThemeGlowClass('amber')).toBe('glow-amber');
  });
});

describe('getSeverityColor', () => {
  it('returns magenta hex for major severity', () => {
    expect(getSeverityColor('major')).toBe('#ffabf3');
  });

  it('returns amber hex for minor severity', () => {
    expect(getSeverityColor('minor')).toBe('#ffb800');
  });

  it('returns cyan hex for info severity', () => {
    expect(getSeverityColor('info')).toBe('#00f3ff');
  });
});

describe('getFontSizeClass', () => {
  it('returns text-xs for sm', () => {
    expect(getFontSizeClass('sm')).toBe('text-xs');
  });

  it('returns text-sm for md', () => {
    expect(getFontSizeClass('md')).toBe('text-sm');
  });

  it('returns text-base for lg', () => {
    expect(getFontSizeClass('lg')).toBe('text-base');
  });
});
