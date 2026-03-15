import clsx from 'clsx';
import Link from '@docusaurus/Link';

type FeatureItem = {
  icon: string;
  title: string;
  description: string;
  link: string;
};

const FeatureList: FeatureItem[] = [
  {
    icon: '🏗️',
    title: '멀티리전 아키텍처',
    description: 'us-east-1 / us-west-2 Active-Active 구성으로 99.99% 가용성을 보장하는 Write-Primary/Read-Local 패턴',
    link: '/architecture/overview',
  },
  {
    icon: '⚙️',
    title: '20개 마이크로서비스',
    description: 'Go, Java, Python으로 구현된 도메인별 마이크로서비스 (Core, User, Fulfillment, Business, Platform)',
    link: '/services/overview',
  },
  {
    icon: '🗄️',
    title: 'Polyglot Persistence',
    description: 'Aurora PostgreSQL, DocumentDB, ElastiCache Valkey, OpenSearch, MSK Kafka - 워크로드별 최적화된 데이터 스토어',
    link: '/architecture/data',
  },
  {
    icon: '☁️',
    title: 'AWS 인프라스트럭처',
    description: 'Terraform으로 관리되는 260+ 리소스, EKS 클러스터, VPC 3-tier 네트워크, CloudFront CDN',
    link: '/infrastructure/overview',
  },
  {
    icon: '🔄',
    title: '이벤트 기반 아키텍처',
    description: 'MSK Kafka 35개 토픽, SAGA 패턴, CQRS, Change Stream을 활용한 비동기 서비스 간 통신',
    link: '/architecture/event-driven',
  },
  {
    icon: '📊',
    title: '관측성 스택',
    description: 'OpenTelemetry, Grafana Tempo, Prometheus, X-Ray를 통한 분산 추적, 메트릭, 로깅',
    link: '/observability/overview',
  },
];

function Feature({icon, title, description, link}: FeatureItem) {
  return (
    <div className={clsx('col col--4')} style={{marginBottom: '2rem'}}>
      <Link to={link} style={{textDecoration: 'none'}}>
        <div className="feature-card">
          <div className="feature-card__icon">{icon}</div>
          <div className="feature-card__title">{title}</div>
          <div className="feature-card__description">{description}</div>
        </div>
      </Link>
    </div>
  );
}

export default function HomepageFeatures(): JSX.Element {
  return (
    <section style={{padding: '4rem 0'}}>
      <div className="container">
        <div className="row">
          {FeatureList.map((props, idx) => (
            <Feature key={idx} {...props} />
          ))}
        </div>
      </div>
    </section>
  );
}
