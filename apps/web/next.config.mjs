/** @type {import('next').NextConfig} */
const nextConfig = {
  // The shared business rules are TypeScript in packages/shared; Next compiles them here.
  transpilePackages: ['@mitralink/shared'],
  reactStrictMode: true,
};

export default nextConfig;
