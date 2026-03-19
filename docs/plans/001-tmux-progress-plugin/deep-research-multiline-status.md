# Comprehensive Guide to tmux Multi-Line Status Bar Configuration and Plugin Development

This report provides an extensive analysis of tmux's multi-line status bar feature, focusing on how to architect plugins that safely leverage additional status lines without disrupting existing user configurations. The research draws from official tmux documentation, changelog entries, real-world plugin examples, and community issue discussions to establish definitive best practices for plugin developers.

## Executive Summary

The **multi-line status bar feature in tmux** enables terminal multiplexer users to display information across multiple horizontal lines at the bottom (or top) of the terminal window[3][3]. This capability, available since **tmux version 2.9 (May 2019)**, fundamentally changed how developers can design status bar plugins by providing flexibility to distribute content across multiple lines rather than attempting to compress everything into a single crowded status line[49][36]. The feature is controlled through the `status` option (which accepts values from `off`, `on`, `2`, `3`, `4`, or `5` to specify the number of lines) and the `status-format[]` array option, where each index corresponds to one status line. Understanding the architectural nuances of this system is critical for plugin developers who want to create non-intrusive additions to the tmux status bar ecosystem.

## Architectural Foundation: Understanding tmux's Status Line System

### Historical Context and Evolution

Before tmux version 2.9, the status line was fundamentally limited to a single horizontal line containing three conceptual regions: the left section (controlled by `status-left`), the center section containing the window list, and the right section (controlled by `status-right`)[11][14][21]. This design constraint forced plugin developers into uncomfortable compromises where they either crowded information into the left or right sections or completely replaced the standard status formatting through heavyweight plugins like tmux-powerline[13][21]. The original status line was automatically refreshed at intervals specified by the `status-interval` option, but the architectural limitation of a single line meant that sophisticated information displays required creative workarounds or external solutions[21][11][11].

The introduction of multi-line status support in tmux 2.9 represented a paradigm shift in how the status bar could be architected[3][49]. Rather than simply expanding the vertical space available, the tmux maintainers took an approach of allowing users and plugins to entirely define each status line's content through the `status-format[]` option, where each line is specified as a separate array element. This architectural choice has profound implications for how plugins should be designed, as it allows a plugin to target a specific line index without necessarily affecting other lines, provided the plugin is designed with awareness of line ordering and safety checks[1][2][2].

### The `status` Option: Valid Values and Line Count

The `status` option controls both whether the status line is displayed and how many lines comprise the status area[9][9]. The valid values are:

- `off`: The status line is entirely hidden from the display[11][14]
- `on`: A single status line is displayed (equivalent to `status 1`)[4][4]
- `2`, `3`, `4`, `5`: Multiple status lines are displayed, with the number indicating the total count of lines[9][9]

When `status 2` is configured, tmux renders two horizontal lines. When `status 3` is configured, three lines appear, and so forth. The tmux man page explicitly states this in its description: "Show or hide the status line or specify its size. Using on gives a status line one row in height; 2, 3, 4 or 5 more rows."[9][9] This means the maximum supported value is `5`, allowing for up to five simultaneous status lines, though in practice most users and plugins utilize either one or two lines.

### Line Numbering and Spatial Ordering

A critical detail for plugin developers is understanding the spatial orientation and indexing scheme for status lines. When `status 2` is configured, **line 0 (`status-format`) corresponds to the topmost status line, and line 1 (`status-format[1]`) corresponds to the bottom status line adjacent to the pane content**[1][2][1][3]. This can be counterintuitive initially, as one might expect index 0 to represent the closest line to the terminal content, but the numbering proceeds from top to bottom within the status area[1]. The `status-position` option (which can be set to `top` or `bottom`) controls whether the entire status block appears above or below the pane content, but the line numbering within that block always proceeds from the top index to the bottom[29][29][9].

For a plugin developer implementing a progress indicator on a second status line, this ordering is significant. If the user has explicitly configured `status 2` with their own content on line 0, a plugin attempting to modify line 0 would overwrite that content. Therefore, sophisticated plugins must check the current status line count and intelligently select which line to target, or provide configuration options allowing users to specify which line the plugin should use[1][2].

## Technical Mechanisms: status-format and Format Expansion

### The status-format[] Array Option

Each status line is defined by a corresponding entry in the `status-format[]` array[9][9]. For a single-line status bar (`status 1` or `status on`), only `status-format` is evaluated. For a two-line status bar (`status 2`), both `status-format` and `status-format[1]` are evaluated and rendered. The format string for each line uses the same templating system as `status-left` and `status-right`, supporting format variables like `#{session_name}`, `#{window_index}`, color codes in the form `#[fg=red,bg=blue]`, and shell command execution via `#(command)` syntax[26][26][26].

The critical architectural distinction is that when multi-line status is enabled, **the entire status line layout is defined through the `status-format[]` array, and the traditional `status-left`, `status-right`, and window-list options are effectively superseded**[2][2][45]. This is documented in the tmux source code and changelog but represents a subtle breaking change that caught many users during the 2.8 to 2.9 upgrade. The man page notes: "Specify the format to be used for each line of the status line."[9][9] This means each `status-format[N]` entry is responsible for defining the complete content of that line, including any left-aligned, centered, or right-aligned elements.

### Format String Syntax and Alignment Directives

Within each `status-format[]` string, content is positioned using alignment directives embedded in the format string[1][1]. The three primary alignment directives are:

- `#[align=left]`: Positions subsequent content at the left edge of the status line
- `#[align=centre]`: Positions subsequent content in the horizontal center
- `#[align=right]`: Positions subsequent content at the right edge

These directives are cumulative within a single format string. For example, the configuration demonstrated in successful real-world implementations combines these directives to create a multi-section status line on a single line[1][1]:

```
set -g status-format '#[align=left]Left content' '#[align=centre]Center content' '#[align=right]Right content'
```

The actual implementation involves appending to the format string using the `-a` flag to `set -g`, allowing multiple statements to build up the complete format string[1][1]:

```
set -g status-format '#[align=left]Session: #S'
set -ag status-format '#[align=centre]#W'
set -ag status-format '#[align=right]%H:%M'
```

This approach allows for more readable configuration files and enables plugins to append to existing format strings without completely overwriting them, provided the plugin uses the `-a` (append) flag correctly.

### Shell Command Expansion with #()

The `#(command)` syntax within format strings executes a shell command and interpolates its output into the status line[4][5][26][26][42][5]. This mechanism is fundamental to plugin architecture because it allows dynamic content generation. When a format string contains `#(hostname)`, tmux executes the `hostname` command and embeds the result directly in the rendered status line[5][5][5]. The command is executed once per `status-interval` period (default 15 seconds, configurable), and the output is cached between refreshes for performance reasons[31][46].

For multi-line status bar plugins, this means a plugin can implement a bash script that generates the appropriate content for a specific status line and embed the call to that script within the corresponding `status-format[N]` entry. For example, a plugin that displays progress indicators could define its content as[3][3]:

```
set -g status-format[1] '#[align=right]#(~/.tmux/plugins/myplugin/progress.sh)'
```

Each time tmux refreshes the status line (at the interval specified by `status-interval`), the `progress.sh` script is executed, and its output is placed on line 1 at the right alignment. This enables real-time progress tracking, battery status display, or other dynamically-generated content.

## Performance Considerations and Optimization

### Status Interval Behavior

The `status-interval` option controls the refresh rate for the status line, specified in seconds[46]. The default value is 15 seconds, meaning all shell commands within `status-format[]` strings are executed at most once every 15 seconds. For plugins implementing progress indicators or real-time monitoring, this can be set more aggressively (e.g., `set -g status-interval 1` for 1-second refresh), but there are important performance implications[3][5][10][5].

However, an important architectural detail is that `status-interval` represents a **maximum interval between refreshes, not a guaranteed minimum**[31]. The tmux developers documented this behavior: "status-interval is a maximum not a minimum. If you are using tmux and it needs to redraw the status line more often, it will."[31] This means if the user interacts with tmux (presses a key, resizes a pane, creates a window), the status line is redrawn immediately rather than waiting for the interval to elapse. Additionally, if shell commands in the status line take longer than one second to complete, they are only executed once per second regardless of the configured interval, to prevent excessive shell spawning[31].

### Scrollback Performance Impact

A documented performance issue affects multi-line status bars specifically when they contain shell command expansions (`#()` directives)[10][10]. When the tmux pane contains a very large scrollback buffer (tens of millions of lines), and the status line contains shell commands, the status line refresh can become extremely slow or appear to hang[10]. This happens because tmux must re-evaluate the format string for each refresh, and if the shell command is expensive, it compounds the performance degradation with large scrollback buffers. The issue was reported and discussed in detail but remains a known limitation when combining large scrollback with complex status-format definitions[10][10].

For plugin developers, the implication is that shell commands in status-format strings should complete very quickly. Instead of executing expensive computations directly in the shell command, it is preferable to maintain state in a file that is updated asynchronously and simply read that file in the shell command invoked from the status line[10][10]. For example, rather than computing system load in the status line itself, a separate background process could update a file with current load data, and the status line would simply `cat` that file.

### Caching and File-Based State

The most performant approach for plugins leveraging multi-line status bars is to decouple the status-format content generation from expensive computations. A plugin could implement a two-part architecture where:

1. A background daemon or cron job updates a state file with current information
2. The status-format[] entries contain shell commands that read from that file and format the output

This pattern is explicitly recommended in the tmux community and is used by sophisticated plugins like tmux-powerline and commercial monitoring tools. The progress indicator example from the search results demonstrates this pattern: a separate process writes the current status to `/tmp/claude-summary`, and the status-format entries contain `#(cat /tmp/claude-summary)` to retrieve and display that cached content[3][3].

## Multi-Line Status Bar Configuration: Practical Architecture

### Default Format Behavior

When multi-line status is first enabled by setting `status 2` (or higher), tmux uses default format strings for any `status-format[N]` entries that are not explicitly configured. The default behavior for line 0 in a multi-line configuration replicates the traditional three-section layout (left, center window list, right) using the extended format syntax[1][2][1][9]. Understanding these defaults is important for plugins because it means simply setting `status 2` without explicitly configuring `status-format[]` entries will still display a functional status line, but a plugin adding content to line 1 would appear below the default line 0.

The tmux changelog for version 2.9 indicates that "the status line can now be configured as a single string"[49], referring to the ability to completely customize each line through `status-format[]`. This represents a fundamental shift from the older approach where the window list was automatically generated and always appeared in the center.

### Plugin Integration Patterns

A well-designed plugin that adds a second status line should follow these architectural principles:

First, the plugin should be able to detect the current status line configuration and determine whether it should add a line or modify an existing one. This detection involves reading the current value of the `status` option and checking what is already configured on any target line[1][2]. Second, the plugin should provide configuration variables allowing users to specify which line it should target, defaulting to a sensible choice like line 1 if `status 2` is already configured[3][3]. Third, the plugin should use the append flag (`-a` or `-ag`) when modifying status-format entries to avoid completely overwriting user configurations[1][1].

The example from the research demonstrates this approach. When enabling a two-line status bar with tmux-powerline or catppuccin/tmux, users can configure plugin-specific variables to control which line is used and what content appears on each line[3][13][19][3]. The plugins read these variables and construct appropriate `status-format[]` entries that incorporate both the user's requested content and the plugin's additions.

## Styling Individual Status Lines

### Per-Line Style Directives

Each status line can have different visual styling (colors, bold, underline, etc.) applied independently through inline style directives within the format string[5][11][14][29][11]. The syntax for inline styles uses the `#[attribute=value]` notation, where attributes include `fg` (foreground color), `bg` (background color), `bold`, `dim`, `italic`, `underline`, etc.[11][14][21][29][11]. These directives reset at the next style directive or when `#[default]` is encountered, allowing for fine-grained control of appearance within a single line[11][14][29].

For example, to create a distinctly-styled second status line:

```
set -g status-format[1] '#[bg=colour235,fg=colour248] Progress: #(~/.tmux/plugin/progress.sh) #[default]'
```

This syntax applies a dark background (colour235) and light gray text (colour248) to the progress indicator on line 1. Importantly, the `#[default]` directive resets to the default style, which inherits from `status-style`[45]. The relationship between `status-style` and inline format directives is that `status-style` provides a baseline default, and inline directives override that default for specific regions of the format string[11][14][29][45].

A subtle but important architectural detail is that when `status-format[]` entries are fully customized (as opposed to using the legacy `status-left` / `status-right` / window-list approach), the entire styling must be specified inline within the format string itself, because the system does not automatically apply `status-style` to regions not explicitly styled[45]. This differs from the pre-2.9 behavior where `status-style` would apply to the entire status line. The tmux maintainers intentionally changed this to allow full flexibility in per-line styling but documented it poorly, causing confusion during the 2.8 to 2.9 migration[45][48][50].

### 256-Color and RGB Support

Modern versions of tmux (3.1 and later) support both the standard 256-color palette and full 24-bit RGB colors[36][11][9][36]. Format strings can specify colors using multiple notations:

- Named colors: `#[fg=red,bg=blue]`
- 256-color palette: `#[fg=colour123,bg=colour234]`
- 24-bit RGB hex: `#[fg=#ff0000,bg=#00ff00]`

For plugins targeting a wide range of user setups, the safest approach is to use named colors or 256-color codes (which have been stable for many tmux versions), with RGB support as an optional enhancement for users with modern terminals[11][14][21][29][11].

## Real-World Plugin Examples and Patterns

### tmux-powerline Architecture

The tmux-powerline plugin represents a mature, well-designed implementation that predates multi-line status support but has evolved to leverage it in recent versions[13][18][48]. The plugin uses a modular segment architecture where each segment is a standalone bash script that produces output for the status bar. tmux-powerline originally implemented its multi-line support through complex shell command composition, but modern versions can utilize the native multi-line status support by generating appropriate `status-format[]` entries for each line[13][18].

The plugin architecture demonstrates best practices including: configuration through a separate config file rather than directly modifying the user's .tmux.conf, auto-detection of available system information to display (battery, CPU load, weather, etc.), and graceful degradation when certain information is unavailable[13][18].

### Catppuccin/tmux Theme Implementation

The Catppuccin tmux theme provides another contemporary example of sophisticated status bar architecture[19][23][18][11]. This theme package integrates with the native multi-line status support by providing configuration variables that allow users to select which status-format line the theme should target. The Catppuccin approach involves:

1. Providing sensible default values for status-format if not already configured
2. Allowing users to customize specific segments through configuration variables
3. Using the `-F` flag with `set -g` to enable format expansion within option values, allowing dynamic status content[7][19]

The implementation demonstrates the use of user options (prefixed with `@`) to store configuration, which the theme then references within status-format[] entries through `#{E:@variable_name}` syntax to expand the variable content[19][26][26].

### AI Agent Session Summary Example

A particularly innovative example from the research demonstrates using multi-line status bars for real-time session context, specifically generating AI-generated summaries of ongoing tmux sessions[3][3]. This implementation:

1. Sets `status 2` to enable two lines
2. Defines `status-format` to display the summary on the first line with session name and time on the right
3. Defines `status-format[1]` to display continuation of the summary on the second line with branch information and context window usage on the right
4. Uses a shell script to intelligently split the summary across two lines based on terminal width

This example is valuable for plugin developers because it demonstrates how to use `#()` expansion to call a custom script that handles line-wrapping and width-aware formatting, allowing for sophisticated content that spans multiple status lines[3][3].

## Safety Considerations for Plugin Architecture

### Detecting and Preserving Existing Configuration

When a plugin implements multi-line status bar support, it must safely interact with potentially existing multi-line configurations. The recommended approach involves:

1. Reading the current `status` option value to determine the number of existing lines
2. Reading the current `status-format[]` values to identify what content already exists
3. Determining an appropriate target line that does not conflict with existing content, or prompting the user to specify a preference
4. Using the append flag (`-ag`) when modifying format strings to preserve existing content rather than overwriting it

A plugin can read the current status configuration using tmux commands:

```bash
current_status=$(tmux show -g status | cut -d' ' -f2)
current_format=$(tmux show -g status-format[1])
```

With this information, the plugin can make intelligent decisions about whether to enable multi-line status and which line to target.

### Configuration Isolation and User Control

Well-designed plugins provide configuration options allowing users to control whether and how the plugin participates in multi-line status display. This might include:

- A variable specifying whether to enable multi-line status (e.g., `@plugin_enable_multiline`)
- A variable specifying which line to target (e.g., `@plugin_status_line 1`)
- Options to control what content appears on each line

These configuration variables are typically stored as user options (prefixed with `@`) in the tmux configuration, allowing them to be read by the plugin and adapted to during initialization[19][22][23][22][22].

### Preventing Conflicts Between Plugins

In complex tmux setups where multiple plugins may interact with status lines, conflicts can arise if multiple plugins attempt to modify the same `status-format[N]` entry. Best practices to prevent this include:

1. Providing clear documentation of which status line(s) the plugin uses
2. Allowing users to manually specify alternative lines if conflicts arise
3. Using the append flag to add content to existing lines rather than overwriting them
4. Following a naming convention for user variables to avoid collisions

The tmux community has not converged on a formal plugin standard for multi-line status coordination, but the patterns emerging from mature plugins suggest that clear configuration options and documentation of line usage are essential.

## Implementation Considerations for Plugin Development

### Bash Script Integration Pattern

For a bash-based TPM plugin implementing a progress indicator on a second status line, the recommended architecture involves:

1. The main plugin file (typically `myplugin.tmux`) detects the current tmux configuration and enables multi-line status if needed
2. The plugin sources a bash script that contains helper functions for rendering progress indicators
3. The plugin appends a call to the progress script into `status-format[1]` using the `#()` syntax
4. The progress script outputs formatted text (with color codes) that is rendered in the status line

The actual implementation might look like:

```bash
#!/usr/bin/env bash
# ~/.tmux/plugins/myplugin/myplugin.tmux

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE}")" && pwd)"

# Enable multi-line status if not already
current_status=$(tmux show -gq status)
if [[ "$current_status" == "1" ]] || [[ "$current_status" == "on" ]]; then
    tmux set -g status 2
fi

# Add plugin content to line 1
tmux set -agF status-format[1] "#[align=right] #($PLUGIN_DIR/progress.sh)"
```

This pattern ensures that the plugin adds its content to line 1 (assuming line 0 remains available for the user's configuration) and uses the `-a` flag to append rather than overwrite.

### Testing and Validation

Plugin developers should test their multi-line implementations across different tmux versions (at minimum 2.9 and current versions) and with different existing status configurations. Test scenarios should include:

1. Fresh tmux setup with no existing status-format configuration
2. Existing single-line status bar with custom status-left and status-right
3. Existing multi-line status bar (status 2, 3, 4, 5)
4. Combinations with other popular plugins that also modify status lines

Validation should confirm that:

- The plugin correctly detects existing configurations
- The plugin does not overwrite user content
- Multiple plugin instances do not conflict
- Performance is acceptable with the configured status-interval
- The output is visually correct across different terminal width configurations

## Limitations and Edge Cases

### Terminal Emulator Compatibility

While multi-line status bars are implemented in tmux itself, some terminal emulators have incomplete support for certain advanced features that affect status bar rendering. Notably, some users reported issues with Alacritty not correctly offsetting cursor position when multi-line status bars are enabled, causing visual artifacts in copy mode[12][12][27][12][34]. These compatibility issues typically manifest as display glitches rather than functional failures, but plugin developers should be aware that some users may experience rendering issues beyond the plugin's control.

### Interaction with Popup Windows and Copy Mode

Multi-line status bars can interact unexpectedly with tmux's popup window feature and copy mode. When a popup window is displayed, it may overlap with or completely obscure status lines, and the interaction behavior depends on both the tmux version and the specific terminal emulator[12][27][12]. Copy mode similarly may have rendering artifacts when multiple status lines are enabled, particularly with certain terminal emulators[27][34].

### Performance with Expensive Shell Commands

As documented earlier, shell commands in status-format[] entries should complete very quickly. Complex commands or commands that access remote systems (e.g., checking battery status on macOS, querying cloud APIs) can significantly impact tmux responsiveness if they are executed directly in the status-format[] entry[10][10][31]. The recommended mitigation is to decouple expensive computations from the status-format rendering through background processes and file-based state caching.

### Interaction with Status Position and Terminal Resizing

When `status-position` is set to `top` rather than the default `bottom`, the multi-line status block appears above the pane content. This generally works well, but some terminal emulators or window managers may have unexpected interactions with top-positioned status bars, particularly when the terminal is resized or when multiple tmux sessions are visible simultaneously. Plugin developers should test their implementations with both `status-position top` and `status-position bottom` configurations.

## Version Compatibility and Migration

### Minimum Version Requirements

The multi-line status bar feature requires tmux version 2.9 or later[3][3][49]. Plugins targeting only tmux 2.9+ can freely use the `status` option and `status-format[]` without compatibility concerns. However, plugins aiming to support older tmux versions (2.8 and earlier) must implement fallback behavior that does not attempt to set `status 2` or define `status-format[]` entries, instead relying on the legacy `status-left` and `status-right` options[11][14][21][11][11].

For users upgrading from tmux 2.8 to 2.9, the removal of the legacy `-fg`, `-bg`, and `-attr` options for status styling required migration of configuration files to use the new `-style` options[48][49][50]. Plugins should be aware of this migration requirement and document it clearly for users upgrading from older configurations.

### Forward Compatibility Considerations

As tmux continues to evolve beyond version 3.6, the basic multi-line status bar feature has remained stable and is unlikely to change significantly. However, developers should monitor tmux changelog entries for potential enhancements to the format system or status-format behavior. Currently, the maximum number of status lines is fixed at 5, though this could theoretically be increased in future versions.

## Recommendations and Best Practices

### For Plugin Developers

1. **Provide Configuration Options**: Allow users to specify which status line the plugin should target, defaulting to a sensible choice that minimizes conflicts with likely user configurations.

2. **Use Append Operations**: When modifying status-format[] entries, use the `-a` (append) flag to preserve existing content rather than overwriting it with `set -g`.

3. **Implement Detection Logic**: Read the current `status` and `status-format[]` configuration before making changes, and adapt the plugin's behavior based on what is already configured.

4. **Optimize Shell Commands**: Ensure that any shell commands executed via `#()` in status-format[] entries complete quickly (under 100 milliseconds). Use background processes and file-based caching for expensive operations.

5. **Test Across Configurations**: Validate the plugin works with various existing status configurations, different tmux versions (at minimum 2.9 and 3.x), and different terminal emulators.

6. **Document Line Usage**: Clearly document which status line(s) the plugin uses and provide guidance for users who have configured multiple plugins affecting status lines.

7. **Provide Uninstall Cleanup**: When the plugin is disabled or uninstalled, restore the tmux configuration to a state as close as possible to before installation, or document the manual cleanup steps required.

### For Plugin Users

1. **Understand Existing Configuration**: Before installing a plugin that modifies status lines, understand what status configuration is already in place.

2. **Use Configuration Variables**: Take advantage of plugin configuration variables to customize behavior and avoid conflicts when running multiple plugins.

3. **Monitor Performance**: If status bar rendering becomes slow, check whether multiple expensive shell commands in `status-format[]` entries are competing for execution time.

4. **Test Terminal Compatibility**: Verify that multi-line status displays correctly in your specific terminal emulator, as some have rendering issues.

5. **Maintain Backups**: Keep a backup of your .tmux.conf before installing plugins that modify status configuration.

## Conclusion

The multi-line status bar feature in tmux, available since version 2.9 (May 2019), fundamentally transformed the architectural possibilities for status bar plugins and user customization. By allowing complete control over multiple status lines through the `status-format[]` array and supporting shell command expansion within each line, tmux moved from a constrained three-section layout to a flexible, multi-line system. The feature enables sophisticated plugins like those rendering progress indicators, AI-generated session summaries, or comprehensive system monitoring information.

For plugin developers, successful implementation of multi-line status bar features requires careful attention to configuration detection, safe integration with existing user configurations, and optimization of shell command execution to avoid performance degradation. The most mature plugins in the ecosystem (tmux-powerline, Catppuccin tmux, and newer purpose-built plugins) demonstrate that well-architected plugins provide configuration options, use safe append-based modifications, and handle edge cases gracefully.

The path forward for plugin development should emphasize collaboration, clear documentation, and adherence to emerging community patterns for status line coordination. As more plugins leverage multi-line status bar capabilities, establishing shared conventions will become increasingly important to prevent conflicts and ensure that users can combine multiple plugins without adverse effects. The tmux community, while having evolved a somewhat informal plugin ecosystem compared to more opinionated multiplexers or editors, has begun establishing best practices through the examples of successful, widely-adopted plugins.

Citations:
[1] https://github.com/tmux/tmux/issues/2225
[2] https://github.com/tmux/tmux/issues/1886
[3] https://quickchat.ai/post/tmux-session-summaries-for-parallel-ai-agents
[4] https://github.com/tmux/tmux/wiki/Getting-Started
[5] https://dev.to/brandonwallace/make-your-tmux-status-line-100-better-with-bash-mgf
[6] https://github.com/tmux/tmux/issues/795
[7] https://github.com/catppuccin/tmux/discussions/516
[8] https://github.com/powerline/powerline/issues/2047
[9] https://man7.org/linux/man-pages/man1/tmux.1.html
[10] https://github.com/tmux/tmux/issues/3352
[11] https://arcolinux.com/everything-you-need-to-know-about-tmux-status-bar/
[12] https://github.com/jwilm/alacritty/issues/2505
[13] https://github.com/erikw/tmux-powerline
[14] https://www.baeldung.com/linux/tmux-status-bar-customization
[15] https://github.com/tmux/tmux/issues/1878
[16] https://hamvocke.com/blog/a-guide-to-customizing-your-tmux-conf/
[17] https://github.com/tmux/tmux/wiki/Advanced-Use
[18] https://github.com/rothgar/awesome-tmux
[19] https://github.com/catppuccin/tmux/blob/main/docs/reference/status-line.md
[20] https://github.com/jaclu/tmux-menus/blob/main/CHANGELOG.md
[21] https://tao-of-tmux.readthedocs.io/en/latest/manuscript/09-status-bar.html
[22] https://github.com/tmux-plugins/tpm/issues/85
[23] https://dev.to/govindup63/mastering-tmux-the-terminal-multiplexer-every-developer-should-know-3ko2
[24] https://www.youtube.com/watch?v=oq0QrB70EVI&vl=en
[25] https://gist.github.com/remarkablemark/c366603f6cf364f157a7dd67ad246f8b
[26] https://github.com/tmux/tmux/wiki/Formats
[27] https://github.com/anthropics/claude-code/issues/20618
[28] https://raw.githubusercontent.com/tmux/tmux/3.6a/CHANGES
[29] https://www.youtube.com/watch?v=WwRljAR9N30
[30] https://github.com/tmux-plugins/tmux-cpu/issues/15
[31] https://github.com/tmux/tmux/issues/797
[32] https://github.com/tmux/tmux/issues/2344
[33] https://github.com/jwilm/alacritty/issues/2138
[34] https://github.com/alacritty/alacritty/issues/3642
[35] https://github.com/tmux-plugins/tpm/issues/27
[36] https://github.com/tmux/tmux/blob/master/CHANGES
[37] https://minhajuddin.com/2016/02/06/how-to-fix-guard-crashing-your-tmux-server/
[38] https://github.com/tmuxinator/tmuxinator/issues/695
[39] https://github.com/tmux-plugins/tmux-online-status
[40] https://github.com/tmux/tmux/issues/1755
[41] https://github.com/tmux/tmux/issues/560
[42] https://tmuxai.dev/tmux-formats/
[43] https://lists.pld-linux.org/mailman/pipermail/pld-cvs-commit/Week-of-Mon-20190506/435271.html
[44] https://oneuptime.com/blog/post/2026-03-02-how-to-customize-tmux-configuration-on-ubuntu/view
[45] https://github.com/tmux/tmux/issues/1909
[46] https://media.pragprog.com/titles/bhtmux3/statusbar.pdf
[47] https://github.com/tmux/tmux/issues/2189
[48] https://www.takala.consulting/updated-tmux-conf/
[49] https://raw.githubusercontent.com/tmux/tmux/2.9/CHANGES
[50] https://github.com/tmux/tmux/issues/1689
