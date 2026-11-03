# Fonts

Third-party fonts under the SIL Open Font License 1.1 (see the `OFL-*.txt`
files next to them). They are not covered by the repository's all rights
reserved license.

| File | Family | Used for |
|---|---|---|
| `BarlowCondensed-Medium.ttf` | Barlow Condensed, The Barlow Project Authors | Delve numbers and labels (tabular figures) |
| `BarlowCondensed-SemiBold.ttf` | Barlow Condensed | Delve buttons and emphasis |
| `ShipporiMinchoB1-Bold-Latin.ttf` | Shippori Mincho B1, The Shippori Mincho Project Authors | Delve titles (enemy names) |
| `MPLUSRounded1c-Medium-Latin.ttf` | M PLUS Rounded 1c, The Rounded M+ Project Authors | Town UI text |
| `MPLUSRounded1c-Bold-Latin.ttf` | M PLUS Rounded 1c | Town titles and buttons |
| `KleeOne-SemiBold-Latin.ttf` | Klee One, The Klee Project Authors | Town signage and handwritten notes (the notice board) |

The `-Latin` files are Latin-only subsets of the originals (Shippori
Mincho is 15 MB with Japanese, M PLUS Rounded 3 MB, Klee One 9 MB), made
with fontTools:

```
pyftsubset <Original>.ttf --layout-features='*' \
  --unicodes="U+0020-007E,U+00A0-00FF,U+2010-2027,U+2030-203A,U+2190-2193,U+2212,U+00D7"
```

Klee One was also subset with `--no-hinting`. Re-subset from the original
when text needs kana or kanji.
