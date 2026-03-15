import type {SidebarsConfig} from '@docusaurus/plugin-content-docs';

const sidebars: SidebarsConfig = {
  docsSidebar: [
    'intro',
    {
      type: 'category',
      label: '시작하기',
      link: {type: 'generated-index', slug: '/getting-started'},
      items: [
        'getting-started/prerequisites',
        'getting-started/quick-start',
        'getting-started/local-development',
        'getting-started/project-structure',
      ],
    },
    {
      type: 'category',
      label: '아키텍처',
      link: {type: 'doc', id: 'architecture/overview'},
      items: [
        'architecture/multi-region-design',
        'architecture/network',
        'architecture/data',
        'architecture/event-driven',
        'architecture/disaster-recovery',
        'architecture/security',
      ],
    },
    {
      type: 'category',
      label: '서비스',
      link: {type: 'doc', id: 'services/overview'},
      items: [
        {
          type: 'category',
          label: 'Core',
          items: [
            'services/core/api-gateway',
            'services/core/product-catalog',
            'services/core/search',
            'services/core/cart',
            'services/core/order',
            'services/core/payment',
            'services/core/inventory',
          ],
        },
        {
          type: 'category',
          label: 'User',
          items: [
            'services/user/user-account',
            'services/user/user-profile',
            'services/user/wishlist',
            'services/user/review',
          ],
        },
        {
          type: 'category',
          label: 'Fulfillment',
          items: [
            'services/fulfillment/shipping',
            'services/fulfillment/warehouse',
            'services/fulfillment/returns',
          ],
        },
        {
          type: 'category',
          label: 'Business',
          items: [
            'services/business/pricing',
            'services/business/recommendation',
            'services/business/notification',
            'services/business/seller',
          ],
        },
        {
          type: 'category',
          label: 'Platform',
          items: [
            'services/platform/event-bus',
            'services/platform/analytics',
          ],
        },
      ],
    },
    {
      type: 'category',
      label: '인프라스트럭처',
      link: {type: 'doc', id: 'infrastructure/overview'},
      items: [
        'infrastructure/terraform-modules',
        'infrastructure/eks-cluster',
        {
          type: 'category',
          label: '데이터베이스',
          items: [
            'infrastructure/databases/aurora-global',
            'infrastructure/databases/documentdb-global',
            'infrastructure/databases/elasticache-global',
            'infrastructure/databases/opensearch',
            'infrastructure/databases/msk',
          ],
        },
        {
          type: 'category',
          label: '엣지',
          items: [
            'infrastructure/edge-cloudfront',
            'infrastructure/edge-waf',
          ],
        },
      ],
    },
    {
      type: 'category',
      label: '배포',
      link: {type: 'doc', id: 'deployment/overview'},
      items: [
        'deployment/gitops-argocd',
        'deployment/ci-cd-pipeline',
        'deployment/kustomize-overlays',
        'deployment/rollout-strategy',
      ],
    },
    {
      type: 'category',
      label: '관측성',
      link: {type: 'doc', id: 'observability/overview'},
      items: [
        'observability/distributed-tracing',
        'observability/metrics-prometheus',
        'observability/logging',
        'observability/dashboards',
      ],
    },
    {
      type: 'category',
      label: '운영',
      link: {type: 'generated-index', slug: '/operations'},
      items: [
        'operations/disaster-recovery',
        'operations/failover-procedures',
        'operations/seed-data',
        'operations/troubleshooting',
      ],
    },
  ],
};

export default sidebars;
