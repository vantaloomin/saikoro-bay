# Fonts

Third-party fonts under the SIL Open Font License 1.1 (see the `OFL-*.txt`
files next to them). They are not covered by the repository's all rights
reserved license.

| File | Family | Used for |
|---|---|---|
| `BarlowCondensed-Medium.ttf` | Barlow Condensed, The Barlow Project Authors | Delve numbers and labels (tabular figures) |
| `BarlowCondensed-SemiBold.ttf` | Barlow Condensed | Delve buttons and emphasis |
| `ShipporiMinchoB1-Bold-Latin.ttf` | Shippori Mincho B1, The Shippori Mincho Project Authors | Delve titles (enemy names) |

`ShipporiMinchoB1-Bold-Latin.ttf` is a Latin-only subset of the original
(15 MB with Japanese), made with fontTools:

```
pyftsubset ShipporiMinchoB1-Bold.ttf --layout-features='*' \
  --unicodes="U+0020-007E,U+00A0-00FF,U+2010-2027,U+2030-203A,U+2190-2193,U+2212,U+00D7"
```

Re-subset from the original when titles need kana or kanji.
