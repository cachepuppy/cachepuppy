/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  // The @cachepuppy/* SDK packages are linked via file: paths and ship as ESM
  // with .js extensions in their imports. Next.js 15 transpiles them through
  // SWC just fine, but we list them here so workspaces resolve cleanly.
  transpilePackages: ["@cachepuppy/core", "@cachepuppy/react"],
};

export default nextConfig;
