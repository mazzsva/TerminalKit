#!/bin/zsh
set -e -o pipefail
cd ${0:A:h}/..
list=Scripts/unused-functions.txt

if ! output=$(swift test --enable-code-coverage --skip TerminalCoreTests --skip SpeedTests 2>&1); then
    print -r -- ${output//$HOME/\~}
    exit 1
fi
runs=(${(M)${(f)output}:#*Test run with * passed after *})
if [[ ${#runs} != 2 ]]; then
    print 'A test run stopped before its end'
    exit 1
fi

listed=(${${(f)"$(<$list)"}:# *})
claude=(${(f)"$(awk '/^ +only the real Claude Code session uses it$/ { print name } /^[^ ]/ { name = $0 }' $list)"})
if [[ $output == *'Test claudeCode() passed'* ]]; then
    print 'The real Claude Code session ran'
    expected=(${listed:|claude})
else
    print 'The real Claude Code session did not run'
    expected=($listed)
    claude=()
fi

bin=$(swift build --show-bin-path)
records=(${(f)"$(xcrun llvm-cov export -instr-profile $bin/codecov/default.profdata \
    $bin/TerminalKitTests.xctest/Contents/MacOS/TerminalKitTests \
    -object $bin/BadInputTests.xctest/Contents/MacOS/BadInputTests |
    /usr/bin/jq -r --arg sources $PWD/Sources/ \
        '.data[0].functions[] | select(.filenames[0] | startswith($sources)) | "\(.count > 0) \(.name)"' |
    xcrun swift-demangle --simplified | grep -v '^[a-z]* implicit closure')"})
all=(${(u)records#* })
unused=(${(u)${(M)records:#false *}#false })

failures=0
report() {
    local name
    for name in ${@[2,-1]}; do
        print -r -- "$1: $name"
        (( failures += 1 ))
    done
}
report 'Unused and not on the list' ${unused:|listed}
report 'Unused, but the real Claude Code session uses it' ${claude:*unused}
report 'On the list, but used' ${${expected:|unused}:*all}
report 'On the list, but gone' ${expected:|all}
if (( failures )); then
    exit 1
fi
print "${#all} functions, and each of the ${#unused} unused ones is on the list"
