import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    coverage: {
      provider: 'v8',
      reporter: ['text', 'lcov'],
      include: ['src/**/*.ts'],
      // ponytail: server.ts chỉ bind port/listen — không test được bằng inject, loại khỏi coverage.
      exclude: ['src/**/*.test.ts', 'src/server.ts'],
      thresholds: {
        lines: 80,
        functions: 80,
        branches: 80,
        statements: 80,
      },
    },
  },
});
