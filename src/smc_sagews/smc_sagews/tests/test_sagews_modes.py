# test_sagews_modes.py
# tests of sage worksheet modes
import pytest
import conftest
import re
from textwrap import dedent

class TestShMode:
    def test_start_sh(self, test_id, sagews):
        code = "%sh\ndate +%Y-%m-%d"
        html_pattern = '\d{4}-\d{2}-\d{2}'
        m = conftest.message.execute_code(code = code, id = test_id)
        m['preparse'] = True
        sagews.send_json(m)
        # skip initial html responses but fail on deprecation warning
        for loop_count in range(5):
            typ, mesg = sagews.recv()
            assert typ == 'json'
            assert mesg['id'] == test_id
            assert 'html' in mesg
            if re.search(html_pattern, mesg['html']) is not None:
                break
        else:
            pytest.fail("sh setup failed %s"%test_id)
        conftest.recv_til_done(sagews, test_id)

    # examples from sh mode docstring in sage_salvus.py
    # note jupyter kernel text ouput is displayed as html
    def test_single_line(self, exec2):
        exec2("%sh pwd\n", html_pattern=">/")

    def test_multiline(self, exec2):
        exec2("%sh\nFOO=hello\necho $FOO", html_pattern="hello")

    def test_direct_call(self, exec2):
        exec2("sh('date +%Y-%m-%d')", html_pattern = '\d{4}-\d{2}-\d{2}')

    def test_capture_sh_01(self, exec2):
        exec2("%capture(stdout='output')\n%sh uptime")
    def test_capture_sh_02(self, exec2):
        exec2("output", pattern="up.*user.*load average")

    def test_remember_settings_01(self, exec2):
        exec2("%sh FOO='testing123'", html_pattern="monospace")

    def test_remember_settings_02(self, exec2):
        exec2("%sh echo $FOO", html_pattern="testing123")

    def test_sh_display(self, execblob, image_file):
        execblob("%sh display < " + str(image_file))

    def test_sh_autocomplete_01(self, exec2):
        exec2("%sh TESTVAR29=xyz")
    def test_sh_autocomplete_02(self, test_id, sagews):
        m = conftest.message.introspect(test_id, line='echo $TESTV', top='%sh')
        m['preparse'] = True
        sagews.send_json(m)
        typ, mesg = sagews.recv()
        assert typ == 'json'
        assert mesg['id'] == test_id
        assert mesg['event'] == "introspect_completions"
        assert mesg['completions'] == ["AR29"]
        assert mesg['target'] == "$TESTV"

    def test_bad_command(self, exec2):
        exec2("%sh xyz", html_pattern="command not found")

class TestShDefaultMode:
    def test_start_sh(self, exec2):
        exec2("%default_mode sh")
    def test_start_sh2(self, exec2):
        exec2("pwd")

    def test_single_line(self, exec2):
        exec2("pwd\n", html_pattern=">/")

    def test_multiline(self, exec2):
        exec2("FOO=hello\necho $FOO", html_pattern="hello")

    def test_date(self, exec2):
        exec2("date +%Y-%m-%d", html_pattern = '\d{4}-\d{2}-\d{2}')

    def test_capture_sh_01(self, exec2):
        exec2("%capture(stdout='output')\nuptime")
    def test_capture_sh_02(self, exec2):
        exec2("%sage\noutput", pattern="up.*user.*load average")

    def test_remember_settings_01(self, exec2):
        exec2("FOO='testing123'", html_pattern="monospace")
    def test_remember_settings_02(self, exec2):
        exec2("echo $FOO", html_pattern="testing123")

    def test_sh_display(self, execblob, image_file):
        execblob("display < " + str(image_file))

    def test_sh_autocomplete_01(self, exec2):
        exec2("TESTVAR29=xyz")
    def test_sh_autocomplete_02(self, test_id, sagews):
        m = conftest.message.introspect(test_id, line='echo $TESTV', top='')
        m['preparse'] = True
        sagews.send_json(m)
        typ, mesg = sagews.recv()
        assert typ == 'json'
        assert mesg['id'] == test_id
        assert mesg['event'] == "introspect_completions"
        assert mesg['completions'] == ["AR29"]
        assert mesg['target'] == "$TESTV"

class TestRMode:
    def test_assignment(self, exec2):
        exec2("%r\nxx <- c(4,7,13)\nmean(xx)", "[1] 8")

    def test_capture_r_01(self, exec2):
        exec2("%capture(stdout='output')\n%r\nsum(xx)")
    def test_capture_r_02(self, exec2):
        exec2("print(output)", "[1] 24\n")

class TestRDefaultMode:
    def test_set_r_mode(self, exec2):
        exec2("%default_mode r")
    def test_assignment(self, exec2):
        exec2("xx <- c(4,7,13)\nmean(xx)", "[1] 8")

    def test_capture_r_01(self, exec2):
        exec2("%capture(stdout='output')\nsum(xx)")
    def test_capture_r_02(self, exec2):
        exec2("%sage\nprint(output)", "[1] 24\n")

class TestOctaveMode:
    def test_start_octave(self, exec2):
        exec2("%octave", html_pattern = "DOCTYPE HTML PUBLIC")

    def test_octave_calc(self, exec2):
        code = "%octave\nformat short\nairy(3,2)\nbeta(2,2)\nbetainc(0.2,2,2)\nbesselh(0,2)"
        outp = "ans =  4.1007\s+ans =  0.16667\s+ans =  0.10400\s+ans =  0.22389 \+ 0.51038i"
        exec2(code, pattern = outp)

    def test_octave_fibonacci(self, exec2):
        code = dedent('''%octave
        fib = ones (1, 10);
        for i = 3:10
            fib(i) = fib(i-1) + fib(i-2);
            printf('%d,', fib(i))
        endfor
        ''')
        outp = '2,3,5,8,13,21,34,55,'
        exec2(code, pattern = outp)

    def test_octave_insync(self, exec2):
        # this just confirms, that input/output is still in sync after the for loop above
        exec2('%octave\n1+1', pattern = 'ans =  2')

class TestOctaveDefaultMode:
    def test_octave_capture1(self, exec2):
        exec2("%default_mode octave")
    def test_octave_capture2(self, exec2):
        exec2("%capture(stdout='output')\nx = [1,2]", html_pattern = "DOCTYPE HTML PUBLIC")
    def test_octave_capture3(self, exec2):
        exec2("%sage\nprint(output)", pattern = "   1   2")

