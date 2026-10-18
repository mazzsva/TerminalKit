import Foundation

enum ShellIntegration {
    static func install(in directory: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let files = [("zsh/.zshenv", zshenv), ("zsh/terminalkit.zsh", zsh), ("bash/terminalkit.bash", bash)]
        let hash = files.flatMap(\.1.utf8)
            .reduce(UInt64(14_695_981_039_346_656_037)) {
                ($0 ^ UInt64($1)) &* 1_099_511_628_211
            }
        let folder = directory.appending(path: "TerminalKit-" + String(hash, radix: 36))
        for (path, content) in files {
            let url = folder.appending(path: path)
            guard (try? String(contentsOf: url, encoding: .utf8)) != content else {
                continue
            }
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(content.utf8).write(to: url, options: .atomic)
        }
        return folder
    }

    private static let zshenv = #"""
        if [[ -n "${TERMINALKIT_ZSH_ZDOTDIR+X}" ]]; then
            'builtin' 'export' ZDOTDIR="$TERMINALKIT_ZSH_ZDOTDIR"
            'builtin' 'unset' 'TERMINALKIT_ZSH_ZDOTDIR'
        else
            'builtin' 'unset' 'ZDOTDIR'
        fi
        {
            'builtin' 'typeset' _terminalkit_file="${ZDOTDIR-$HOME}/.zshenv"
            [[ ! -r "$_terminalkit_file" ]] || 'builtin' 'source' '--' "$_terminalkit_file"
        } always {
            if [[ -o 'interactive' ]]; then
                _terminalkit_file="${${(%):-%x}:A:h}/terminalkit.zsh"
                [[ ! -r "$_terminalkit_file" ]] || 'builtin' 'source' '--' "$_terminalkit_file"
            fi
            'builtin' 'unset' '_terminalkit_file'
        }
        """#

    private static let zsh = #"""
        (( ${+_terminalkit_ps1} )) && 'builtin' 'return' 0
        'builtin' 'typeset' -g _terminalkit_ps1='' _terminalkit_plain_ps1='' _terminalkit_command=0 _terminalkit_zle=0

        _terminalkit_encode() {
            'builtin' 'emulate' -L 'zsh' -o 'extended_glob'
            'builtin' 'local' LC_ALL=C
            REPLY=${1//(#m)[^A-Za-z0-9\/._~-]/%${(l:2::0:)$(( [##16] #MATCH ))}}
        }

        _terminalkit_precmd() {
            'builtin' 'local' -i code=$?
            'builtin' 'emulate' -L 'zsh'
            if (( _terminalkit_command )); then
                _terminalkit_command=0
                'builtin' 'print' -n "\e]133;D;$code\a"
            fi
            'builtin' 'local' REPLY
            _terminalkit_encode "$PWD"
            'builtin' 'print' -n "\e]7;file://$HOST$REPLY\a"
            if [[ ${precmd_functions[1]} != _terminalkit_precmd || ${precmd_functions[-1]} != _terminalkit_prompt ]]; then
                precmd_functions=(_terminalkit_precmd ${precmd_functions:#_terminalkit_(precmd|prompt)} _terminalkit_prompt)
            fi
            if (( ! _terminalkit_zle )); then
                _terminalkit_zle=1
                'builtin' 'autoload' -Uz 'add-zle-hook-widget'
                'add-zle-hook-widget' 'line-init' '_terminalkit_line_init'
            fi
            if [[ ${preexec_functions[-1]} != _terminalkit_preexec ]]; then
                preexec_functions=(${preexec_functions:#_terminalkit_preexec} _terminalkit_preexec)
            fi
        }

        _terminalkit_prompt() {
            'builtin' 'emulate' -L 'zsh'
            [[ $PS1 == "$_terminalkit_ps1" ]] && 'builtin' 'return' 0
            _terminalkit_plain_ps1=$PS1
            'builtin' 'local' ps1=$PS1
            [[ $ps1 == *[^%]% || $ps1 == % ]] && ps1=${ps1%?}
            PS1=$'%{\e]133;A\a%}'$ps1$'%{\e]133;B\a%}'
            _terminalkit_ps1=$PS1
        }

        _terminalkit_line_init() {
            [[ $PS1 == "$_terminalkit_ps1" ]] && 'builtin' 'return' 0
            _terminalkit_prompt
            'builtin' 'zle' 'reset-prompt'
        }

        _terminalkit_preexec() {
            'builtin' 'emulate' -L 'zsh'
            _terminalkit_command=1
            [[ $PS1 != "$_terminalkit_ps1" ]] || PS1=$_terminalkit_plain_ps1
            'builtin' 'local' REPLY=''
            (( ${#1} > 1024 )) || _terminalkit_encode "$1"
            'builtin' 'print' -n "\e]133;C${REPLY:+;cmdline_url=$REPLY}\a"
        }

        'builtin' 'typeset' -ag precmd_functions preexec_functions
        precmd_functions=(_terminalkit_precmd $precmd_functions _terminalkit_prompt)
        preexec_functions+=(_terminalkit_preexec)
        """#

    private static let bash = #"""
        if [[ -n ${TERMINALKIT_BASH_INJECT-} ]]; then
            if [[ $TERMINALKIT_BASH_INJECT == login ]]; then
                builtin unset TERMINALKIT_BASH_INJECT
                [[ -r /etc/profile ]] && builtin source /etc/profile
                for __terminalkit_file in ~/.bash_profile ~/.bash_login ~/.profile; do
                    if [[ -r $__terminalkit_file ]]; then
                        builtin source "$__terminalkit_file"
                        break
                    fi
                done
                builtin unset __terminalkit_file
                logout() {
                    [[ -r ~/.bash_logout ]] && builtin source ~/.bash_logout
                    builtin exit "$@"
                }
            else
                builtin unset TERMINALKIT_BASH_INJECT
                [[ -r ~/.bashrc ]] && builtin source ~/.bashrc
            fi
        fi

        if [[ $- == *i* && -z ${__terminalkit_ps1+X} ]]; then
            __terminalkit_ps1='' __terminalkit_plain_ps1='' __terminalkit_command=0 __terminalkit_prompting=0

            __terminalkit_encode() {
                builtin local LC_ALL=C string="$1" character hex index
                __terminalkit_reply=''
                if [[ $string != *[!A-Za-z0-9/._~-]* ]]; then
                    __terminalkit_reply=$string
                    builtin return 0
                fi
                for (( index = 0; index < ${#string}; index++ )); do
                    character=${string:index:1}
                    case $character in
                        [A-Za-z0-9/._~-]) __terminalkit_reply+=$character ;;
                        *)
                            builtin printf -v hex '%d' "'$character"
                            builtin printf -v hex '%%%02X' $(( hex & 255 ))
                            __terminalkit_reply+=$hex
                            ;;
                    esac
                done
            }

            __terminalkit_precmd() {
                builtin local code=$?
                if [[ $__terminalkit_command == 1 ]]; then
                    __terminalkit_command=0
                    builtin printf '\e]133;D;%s\a' "$code"
                fi
                __terminalkit_encode "$PWD"
                builtin printf '\e]7;file://%s%s\a' "$HOSTNAME" "$__terminalkit_reply"
                builtin return $code
            }

            __terminalkit_prompt() {
                builtin local code=$?
                if [[ $PS1 != "$__terminalkit_ps1" ]]; then
                    __terminalkit_plain_ps1=$PS1
                    PS1='\[\e]133;A\a\]'$PS1'\[\e]133;B\a\]'
                    __terminalkit_ps1=$PS1
                fi
                __terminalkit_prompting=1
                builtin return $code
            }

            __terminalkit_preexec() {
                [[ $__terminalkit_prompting == 1 && -z ${FUNCNAME[1]-} ]] || builtin return 0
                __terminalkit_prompting=0
                [[ $BASH_COMMAND == __terminalkit_precmd ]] && builtin return 0
                __terminalkit_command=1
                [[ $PS1 != "$__terminalkit_ps1" ]] || PS1=$__terminalkit_plain_ps1
                builtin printf '\e]133;C\a'
                builtin return 0
            }

            PROMPT_COMMAND="__terminalkit_precmd${PROMPT_COMMAND:+
        $PROMPT_COMMAND}
        __terminalkit_prompt"
            __terminalkit_capture() {
                __terminalkit_debug=${2-}
            }
            __terminalkit_debug=$(builtin trap -p DEBUG)
            builtin eval "__terminalkit_capture${__terminalkit_debug#trap}"
            builtin trap -- "${__terminalkit_debug:+$__terminalkit_debug
        }__terminalkit_preexec" DEBUG
            builtin unset -f __terminalkit_capture
            builtin unset __terminalkit_debug
        fi
        """#
}
