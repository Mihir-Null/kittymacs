# Sonokai theme port

`doom-sonokai-theme.el` is a standalone Doom Themes port of Sonokai's **default**
style. It is maintained as ordinary theme source, not tangled from Org, so the
same file can be contributed to `doomemacs/themes` without depending on this configuration.

- Original: https://github.com/sainnhe/sonokai
- Source revision: `b023c5280b16fe2366f5e779d8d2756b3e5ee9c3`
- Palette: `autoload/sonokai.vim`, default branch of `sonokai#get_palette`.
- Highlight mappings: `colors/sonokai.vim`, common UI and syntax groups.
- Framework: https://github.com/doomemacs/themes
- License: MIT; the source notice and permission text are retained in the file.

The GUI palette and 256-color fallbacks follow Sonokai. Emacs syntax categories
adapt its traditional and Tree-sitter groups; Doom's shared faces provide broader
package coverage. Other Sonokai variants and Vim-specific options are not ported.

The UI module prepends this directory to `custom-theme-load-path` after loading
`doom-themes`. Keep this source outside `var/elpa`, which package upgrades replace.
If the port is released upstream, compare versions before removing this copy and
its path registration. Font, layout and tab-face policy remain in the literate UI
module.
