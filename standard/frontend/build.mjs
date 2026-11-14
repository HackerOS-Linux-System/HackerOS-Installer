import esbuild from 'esbuild';
import { solidPlugin } from 'esbuild-plugin-solid';

const watch = process.argv.includes('--watch');

const options = {
  entryPoints: ['src/index.tsx'],
  bundle: true,
  format: 'iife',
  target: 'es2020',
  platform: 'browser',
  // klienckie buildy solid-js (nie serwerowe)
  conditions: watch ? ['browser', 'development'] : ['browser'],
  plugins: [solidPlugin()],
  define: { 'process.env.NODE_ENV': watch ? '"development"' : '"production"' },
  minify: !watch,
  sourcemap: false,
  outfile: 'dist/app.js',
  logLevel: 'info',
};

if (watch) {
  const ctx = await esbuild.context(options);
  await ctx.watch();
  console.log('obserwuję zmiany…');
} else {
  await esbuild.build(options);
}
