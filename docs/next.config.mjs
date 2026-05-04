import { createMDX } from "fumadocs-mdx/next";

/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  output: "export",
  // Required for `next/image` with static export (e.g. Cloudflare Pages); no Image Optimization API.
  images: {
    unoptimized: true,
  },
};

const withMDX = createMDX();
export default withMDX(nextConfig);
