/** @type {import('next').NextConfig} */
const nextConfig = {
  images: {
    // Poster berasal dari banyak CDN situs sumber — izinkan semua host https.
    remotePatterns: [{ protocol: 'https', hostname: '**' }],
  },
};

export default nextConfig;
