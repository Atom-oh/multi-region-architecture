import clsx from 'clsx';
import Link from '@docusaurus/Link';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import Layout from '@theme/Layout';
import HomepageFeatures from '@site/src/components/HomepageFeatures';

function HomepageHeader() {
  const {siteConfig} = useDocusaurusContext();
  return (
    <header className="hero">
      <div className="container">
        <h1 className="hero__title">{siteConfig.title}</h1>
        <p className="hero__subtitle">{siteConfig.tagline}</p>
        <div style={{display: 'flex', gap: '1rem', justifyContent: 'center', marginTop: '2rem'}}>
          <Link className="button button--primary button--lg" to="/intro">
            문서 시작하기
          </Link>
          <Link className="button button--secondary button--outline button--lg" to="/architecture/overview">
            아키텍처 보기
          </Link>
        </div>
      </div>
    </header>
  );
}

function Stats() {
  const stats = [
    {number: '20', label: '마이크로서비스'},
    {number: '2', label: '리전 (Active-Active)'},
    {number: '5', label: '데이터 스토어'},
    {number: '35', label: 'Kafka 토픽'},
    {number: '260+', label: 'Terraform 리소스'},
    {number: '<1s', label: 'RPO (복구 시점)'},
  ];

  return (
    <section className="stats-section">
      <div className="container">
        <div className="row">
          {stats.map((stat, idx) => (
            <div key={idx} className="col col--2 stat-item">
              <div className="stat-number">{stat.number}</div>
              <div className="stat-label">{stat.label}</div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

export default function Home(): JSX.Element {
  const {siteConfig} = useDocusaurusContext();
  return (
    <Layout title={siteConfig.title} description={siteConfig.tagline}>
      <HomepageHeader />
      <Stats />
      <main>
        <HomepageFeatures />
      </main>
    </Layout>
  );
}
