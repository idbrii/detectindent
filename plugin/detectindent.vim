" Name:          detectindent (global plugin)
" Version:       1.4
" Author:        Ciaran McCreesh <ciaran.mccreesh at googlemail.com>
" Updates:       http://github.com/ciaranm/detectindent
" Purpose:       Detect file indent settings
"
" License:       You may redistribute this plugin under the same terms as Vim
"                itself.
"
" Usage:         :DetectIndent
"
"                " to prefer expandtab to noexpandtab when detection is
"                " impossible:
"                :let g:detectindent_preferred_expandtab = 1
"
"                " to set a preferred indent level when detection is
"                " impossible:
"                :let g:detectindent_preferred_indent = 4
"                
"                " To use preferred values instead of guessing:
"                :let g:detectindent_preferred_when_mixed = 1
"
"                " To reduce the number of lines inspected:
"                :let g:detectindent_max_lines_to_analyse = 100
"
" Requirements:  Untested on Vim versions below 6.2

if exists("loaded_detectindent")
    finish
endif
let loaded_detectindent = 1

if !exists('g:detectindent_verbosity')
    let g:detectindent_verbosity = 1
endif

if exists('g:detectindent_check_comment_syntax')
    echo "detectindent_check_comment_syntax is deprecated. Use detectindent_check_syntax."
    let g:detectindent_check_syntax = g:detectindent_check_comment_syntax
    unlet g:detectindent_check_comment_syntax
endif

" Ignore comment lines via syntax (slow but accurate):
let g:detectindent_check_syntax = get(g:, 'detectindent_check_syntax', 0)

" Ignore 'comments' when detecting comment blocks.
let g:detectindent_comments_blacklist = get(g:, 'detectindent_comments_blacklist', [])



let s:comment_marker_none = 0
let s:comment_marker_start = 1
let s:comment_marker_end = 2
let s:comment_marker_line = 3
function! s:BuildEmptyMarkerDict()
    let dict = { 'has_block': 0, 'has_line': 0 }
    function! dict.get_matching_marker(line) dict abort
        if self.has_line && stridx(a:line, self.line) > -1
            return s:comment_marker_line
        elseif self.has_block
            let has_start = stridx(a:line, self.start) > -1
            let has_end   = stridx(a:line, self.end) > -1
            if has_start && has_end
                return s:comment_marker_line
            elseif has_start
                return s:comment_marker_start
            elseif has_end
                return s:comment_marker_end
            endif
        end
        return s:comment_marker_none
    endf

    function! dict.IsCommentStart(line) dict abort
        return self.get_matching_marker(a:line) == s:comment_marker_start
    endf
    function! dict.IsCommentEnd(line) dict abort
        return self.get_matching_marker(a:line) == s:comment_marker_end
    endf
    function! dict.IsCommentLine(line) dict abort
        return self.get_matching_marker(a:line) == s:comment_marker_line
    endf
    return dict
endf

function! s:GetCommentMarkers()
    if !exists("b:detectindent_comment_markers")
        let b:detectindent_comment_markers = s:BuildEmptyMarkerDict()
        let is_blacklisted = index(g:detectindent_comments_blacklist, &filetype) >= 0
        if !is_blacklisted
            " &commentstring is usually single-line comments, so we need to look
            " at &comments which looks like this:
            " s:--[[,m: ,e:]],:--
            let dict = {}
            for part in split(&comments, ',')
                let flag_to_str = split(part, ':')
                let num_elements = len(flag_to_str)
                if num_elements == 2
                    " Two-part are sometimes beginning and end.
                    " ignore parts[1] -- the number of characters to indent
                    let parts = split(flag_to_str[0], '\zs')
                    let dict[parts[0]] = flag_to_str[1]
                elseif num_elements == 1
                    " One part are always single-line comments.
                    let dict['line'] = flag_to_str[0]
                endif
            endfor

            let comment_start = get(dict, 's', '')
            let comment_end   = get(dict, 'e', '')
            if len(comment_start) > 0 && len(comment_end) > 0
                " Only accept block if we have both start and end. Default
                " make.vim only sets s,m,b (for bullet lists). Probably
                " omitted e because it didn't add anything.
                let b:detectindent_comment_markers.start = comment_start
                let b:detectindent_comment_markers.end = comment_end
                let b:detectindent_comment_markers.has_block = 1
            endif

            let line = get(dict, 'line', '')
            if len(line) > 0
                let b:detectindent_comment_markers.line = line
                let b:detectindent_comment_markers.has_line = 1
            endif
        endif
    endif
    return b:detectindent_comment_markers
endf

" For easy testing of problematic lines.
"~ function! Debug_GetCommentMarkers(line)
"~     let markers = s:GetCommentMarkers()
"~     return markers.get_matching_marker(a:line)
"~ endf
"~ function! Debug_HasCommentSyntax(line_number)
"~     return s:HasIgnoredSyntax(a:line_number, getline(a:line_number))
"~ endf

fun! s:HasIgnoredSyntax(line_number, line_text) " {{{1
    " Some languages (lua) don't define space before a comment as part of the
    " comment so look at the first nonblank character.
    let nonblank_col = match(a:line_text, '\S') + 1
    let transparent = 1
    let id = synID(a:line_number, nonblank_col, transparent)
    let syntax = synIDattr(id, 'name')
    return syntax =~? 'string\|comment'
endfun

fun! s:GetValue(option)
    if exists('b:'. a:option)
        return get(b:, a:option)
    else
        return get(g:, a:option)
    endif
endfun

fun! s:SetIndent(expandtab, desired_tabstop)
    let &l:expandtab = a:expandtab

    " Only modify tabs if we have a valid value.
    if a:desired_tabstop > 0
        " See `:help 'tabstop'`. We generally adhere to #1 or #4, but when
        " guessing what to do for mixed tabs and spaces we use #2.

        let &l:tabstop = a:desired_tabstop
        " NOTE: shiftwidth=0 keeps it in sync with tabstop, but that breaks
        " many indentation plugins that read 'sw' instead of calling the new
        " shiftwidth(). See
        " https://github.com/tpope/vim-sleuth/issues/25
        let &l:shiftwidth = a:desired_tabstop

        if v:version >= 704
            " Negative value automatically keeps in sync with shiftwidth in Vim 7.4+.
            setl softtabstop=-1
        else
            let &l:softtabstop = a:desired_tabstop
        endif
    endif
endfun

fun! <SID>DetectIndent()
    let l:has_leading_tabs            = 0
    let l:has_leading_spaces          = 0
    let l:shortest_leading_spaces_run = 0
    let l:shortest_leading_spaces_idx = 0
    let l:longest_leading_spaces_run  = 0
    let l:max_lines                   = 1024
    if exists("g:detectindent_max_lines_to_analyse")
      let l:max_lines = g:detectindent_max_lines_to_analyse
    endif

    let verbose_msg = ''
    if ! exists("b:detectindent_cursettings")
      " remember initial values for comparison
      let b:detectindent_cursettings = {'expandtab': &et, 'shiftwidth': &sw, 'tabstop': &ts, 'softtabstop': &sts}
    endif
    
    let can_check_syntax = s:GetValue('detectindent_check_syntax')
    let markers = s:GetCommentMarkers()

    " There's lots of junk at the start of files that would be nice to skip,
    " but we need to start from the top to ensure we know if we're in a
    " comment block.
    let l:idx_end = line("$")
    let l:idx = 1
    while l:idx <= l:idx_end
        let l:line = getline(l:idx)

        " try to skip over comment blocks, they can give really screwy indent
        " settings in c/c++ files especially
        if markers.IsCommentStart(l:line)
            while l:idx <= l:idx_end && markers.IsCommentEnd(l:line)
                let l:idx = l:idx + 1
                let l:line = getline(l:idx)
            endwhile
            let l:idx = l:idx + 1
            continue
        endif

        " Skip comment lines since they are not dependable.
        if markers.IsCommentLine(l:line) || (can_check_syntax && s:HasIgnoredSyntax(l:idx, l:line))
            let l:idx = l:idx + 1
            continue
        endif

        " Skip lines that are solely whitespace, since they're less likely to
        " be properly constructed.
        if l:line !~ '\S'
            let l:idx = l:idx + 1
            continue
        endif

        let l:leading_char = strpart(l:line, 0, 1)

        if l:leading_char == "\t"
            let l:has_leading_tabs = 1

        elseif l:leading_char == " "
            " only interested if we don't have a run of spaces followed by a
            " tab.
            if -1 == match(l:line, '^ \+\t')
                let l:has_leading_spaces = 1
                let l:spaces = strlen(matchstr(l:line, '^ \+'))
                if l:shortest_leading_spaces_run == 0 ||
                            \ l:spaces < l:shortest_leading_spaces_run
                    let l:shortest_leading_spaces_run = l:spaces
                    let l:shortest_leading_spaces_idx = l:idx
                endif
                if l:spaces > l:longest_leading_spaces_run
                    let l:longest_leading_spaces_run = l:spaces
                endif
            endif

        endif

        let l:idx = l:idx + 1

        let l:max_lines = l:max_lines - 1

        if l:max_lines == 0
            let l:idx = l:idx_end + 1
        endif

    endwhile

    if l:has_leading_tabs && ! l:has_leading_spaces
        " tabs only, no spaces
        let l:verbose_msg = "Detected tabs only and no spaces"
        let indent = s:GetValue("detectindent_preferred_indent")
        if indent == 0
            " Default behavior is to retain current tabstop. Still need to set
            " it to ensure softtabstop, shiftwidth, tabstop are in sync.
            let indent = &l:tabstop
        endif
        call s:SetIndent(0, indent)

    elseif l:has_leading_spaces && ! l:has_leading_tabs
        " spaces only, no tabs
        let l:verbose_msg = "Detected spaces only and no tabs"
        call s:SetIndent(1, l:shortest_leading_spaces_run)

    elseif l:has_leading_spaces && l:has_leading_tabs && ! s:GetValue("detectindent_preferred_when_mixed")
        " spaces and tabs
        let l:verbose_msg = "Detected spaces and tabs"
        call s:SetIndent(1, l:shortest_leading_spaces_run)

        " mmmm, time to guess how big tabs are
        if l:longest_leading_spaces_run <= 2
            let &l:tabstop = 2
        elseif l:longest_leading_spaces_run <= 4
            let &l:tabstop = 4
        else
            let &l:tabstop = 8
        endif

    else
        " no spaces, no tabs
        let l:verbose_msg = s:GetValue("detectindent_preferred_when_mixed") ? "preferred_when_mixed is active" : "Detected no spaces and no tabs"
        call s:SetIndent(s:GetValue("detectindent_preferred_expandtab"), s:GetValue("detectindent_preferred_indent"))

    endif

    if &verbose >= g:detectindent_verbosity
        echo l:verbose_msg
                    \ ."; has_leading_tabs:" l:has_leading_tabs
                    \ .", has_leading_spaces:" l:has_leading_spaces
                    \ .", shortest_leading_spaces_run:" l:shortest_leading_spaces_run
                    \ .", shortest_leading_spaces_idx:" l:shortest_leading_spaces_idx
                    \ .", longest_leading_spaces_run:" l:longest_leading_spaces_run

        let changed_msg = []
        for [setting, oldval] in items(b:detectindent_cursettings)
          exec 'let newval = &'.setting
          if oldval != newval
            let changed_msg += [ setting." changed from ".oldval." to ".newval ]
          end
        endfor
        if len(changed_msg)
          echo "Initial buffer settings changed:" join(changed_msg, ", ")
        endif
    endif
endfun

function! s:DetectIfEditable()
    if !exists("b:detectindent_has_tried_to_detect") && !&readonly && &modifiable
        DetectIndent
        let b:detectindent_has_tried_to_detect = 1
    endif
endf
function! s:SetupDetectionAutocmd()
    augroup DetectIndent
        autocmd!
        autocmd BufReadPost * call s:DetectIfEditable()
    augroup END
endf

command! -bar -nargs=0 DetectIndent call <SID>DetectIndent()
command! -bar -nargs=0 AutoDetectIndent call <SID>SetupDetectionAutocmd()

