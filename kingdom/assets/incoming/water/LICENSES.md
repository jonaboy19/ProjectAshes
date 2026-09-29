# Water shader sources and licences

No third-party code or textures were copied into `shaders/water/clear_water.gdshader`.
It extends the project's own `shaders/water.gdshader`; the caustics and foam textures
are generated at runtime (FastNoiseLite cellular / simplex noise). Projects surveyed for
ideas (licence text fetched from GitHub's licence API on 2026-09-29):

| Project | Licence | Use |
|---|---|---|
| Malidos/Stylized-Water-Shader | CC0-1.0 | edge bands / player ripple idea (already credited in water.gdshader) |
| 2Retr0/GodotOceanWaves | MIT | FFT ocean, compute-shader based: too heavy for mobile, NOT used. Optional desktop ULTRA idea only |
| godotshaders.com water shaders | per-shader (check page) | not used |
| Waterways (C#) | skipped | C# |

Also: Vlachos, "Water Flow in Portal 2" (SIGGRAPH 2010) for two-phase flow maps (technique only).

## Malidos/Stylized-Water-Shader - CC0 1.0 Universal
Public-domain dedication; no attribution required. Full text: https://creativecommons.org/publicdomain/zero/1.0/legalcode

## 2Retr0/GodotOceanWaves - MIT (not incorporated; text kept for reference)
MIT License

Copyright (c) 2024 Ethan Truong

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
