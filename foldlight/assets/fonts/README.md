# Foldlight Sans SC

`FoldlightSansSC.woff2` is the bundled Chinese font for the Web export. Desktop builds continue to use their existing system fonts.

The font is derived from [Noto Sans SC](https://github.com/google/fonts/tree/main/ofl/notosanssc), distributed under the [SIL Open Font License 1.1](OFL-NotoSansSC.txt). The upstream variable TTF was instantiated at weight 400 and renamed to Foldlight Sans SC before WOFF2 compression. All 30,890 glyphs were retained; this is not a subset of the current game text.

Source: `https://raw.githubusercontent.com/google/fonts/main/ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf`

Build tools: FontTools 4.65.0 (`varLib.instancer`, `TTFont`) and Brotli. Set `wght=400`, rename name-table IDs 1/3/4/6/16 to the Foldlight family, set IDs 2/17 to Regular, and save with `font.flavor = 'woff2'`. The original copyright and license records are preserved.

The license is included in the Web export alongside the font.
