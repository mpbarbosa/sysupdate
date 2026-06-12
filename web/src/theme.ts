import type { SystemConfig, UpdateItem } from './types';

/** Hex value for a SystemConfig.themeColor, used for inline accent styling. */
export const getThemeColorHex = (themeColor: SystemConfig['themeColor']): string => {
  switch (themeColor) {
    case 'magenta':
      return '#ffabf3';
    case 'emerald':
      return '#39ff14';
    case 'amber':
      return '#ffb800';
    case 'cyan':
    default:
      return '#00f3ff';
  }
};

/** Tailwind text-shadow-style glow class for a SystemConfig.themeColor. */
export const getThemeGlowClass = (themeColor: SystemConfig['themeColor']): string => {
  switch (themeColor) {
    case 'magenta':
      return 'glow-magenta';
    case 'emerald':
      return 'glow-emerald';
    case 'amber':
      return 'glow-amber';
    case 'cyan':
    default:
      return 'glow-cyan';
  }
};

/** Hex value for an UpdateItem.severity badge. */
export const getSeverityColor = (severity: UpdateItem['severity']): string => {
  switch (severity) {
    case 'major':
      return '#ffabf3';
    case 'minor':
      return '#ffb800';
    case 'info':
    default:
      return '#00f3ff';
  }
};

/** Tailwind text size class for a SystemConfig.fontSize. */
export const getFontSizeClass = (fontSize: SystemConfig['fontSize']): string => {
  switch (fontSize) {
    case 'sm':
      return 'text-xs';
    case 'lg':
      return 'text-base';
    case 'md':
    default:
      return 'text-sm';
  }
};
