import {themes as prismThemes} from 'prism-react-renderer';
import type {Config} from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';

const config: Config = {
  title: 'Multi-Region Shopping Mall',
  tagline: 'AWS 기반 멀티리전 마이크로서비스 아키텍처',
  favicon: 'img/favicon.ico',

  url: 'https://atom-oh.github.io',
  baseUrl: '/multi-region-architecture/',

  organizationName: 'Atom-oh',
  projectName: 'multi-region-architecture',

  onBrokenLinks: 'warn',
  onBrokenMarkdownLinks: 'warn',

  i18n: {
    defaultLocale: 'ko',
    locales: ['ko', 'en'],
    localeConfigs: {
      ko: {
        label: '한국어',
        direction: 'ltr',
      },
      en: {
        label: 'English',
        direction: 'ltr',
      },
    },
  },

  markdown: {
    mermaid: true,
    format: 'md',
  },

  themes: ['@docusaurus/theme-mermaid'],

  presets: [
    [
      'classic',
      {
        docs: {
          routeBasePath: '/',
          sidebarPath: './sidebars.ts',
          editUrl: 'https://github.com/Atom-oh/multi-region-architecture/tree/main/webpage/',
        },
        blog: false,
        theme: {
          customCss: './src/css/custom.css',
        },
      } satisfies Preset.Options,
    ],
  ],

  themeConfig: {
    image: 'img/logo.svg',
    navbar: {
      title: 'Multi-Region Mall',
      logo: {
        alt: 'Multi-Region Mall Logo',
        src: 'img/logo.svg',
      },
      items: [
        {
          type: 'docSidebar',
          sidebarId: 'docsSidebar',
          position: 'left',
          label: '문서',
        },
        {
          type: 'localeDropdown',
          position: 'right',
        },
        {
          href: 'https://github.com/Atom-oh/multi-region-architecture',
          label: 'GitHub',
          position: 'right',
        },
      ],
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: '문서',
          items: [
            {label: '시작하기', to: '/getting-started/prerequisites'},
            {label: '아키텍처', to: '/architecture/overview'},
            {label: '서비스', to: '/services/overview'},
          ],
        },
        {
          title: '인프라',
          items: [
            {label: '인프라스트럭처', to: '/infrastructure/overview'},
            {label: '배포', to: '/deployment/overview'},
            {label: '관측성', to: '/observability/overview'},
          ],
        },
        {
          title: '더보기',
          items: [
            {label: 'GitHub', href: 'https://github.com/Atom-oh/multi-region-architecture'},
          ],
        },
      ],
      copyright: `Copyright ${new Date().getFullYear()} Multi-Region Shopping Mall. Built with Docusaurus.`,
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
      additionalLanguages: ['java', 'go', 'hcl', 'bash', 'json', 'yaml', 'sql', 'python'],
    },
    mermaid: {
      theme: {light: 'neutral', dark: 'dark'},
    },
    colorMode: {
      defaultMode: 'light',
      disableSwitch: false,
      respectPrefersColorScheme: true,
    },
  } satisfies Preset.ThemeConfig,

  plugins: [
    [
      require.resolve('@easyops-cn/docusaurus-search-local'),
      {
        hashed: true,
        language: ['ko', 'en'],
        indexBlog: false,
        docsRouteBasePath: '/',
      },
    ],
  ],
};

export default config;
