# -*- coding: utf-8 -*-
# test_sagews.py
# basic tests of sage worksheet using TCP protocol with sage_server
import socket
import conftest
import os
import re

class TestBadContinuation:
    r"""
    String with badly-formed utf8 would hang worksheet process #1866
    """
    def test_bad_utf8(self, exec2):
        code = r"""print('u"\xe1"')"""
        outp = u"�"
        exec2(code, outp)

class TestUnicode:
    r"""
    To pass unicode in a simulated input cell, quote it.
    That will send the same message to sage_server
    as a real input cell without the outer quotes.
    """
    def test_unicode_1(self, exec2):
        r"""
        test for cell with input u"äöüß"
        """
        ustr = 'u"äöüß"'
        uout = ustr[2:-1].decode('utf8').__repr__().decode('utf8')
        exec2(ustr, uout)
    def test_unicode_2(self, exec2):
        r"""
        Test for cell with input u"ááá".
        Input u"ááá" in an actual cell causes latin1 encoding to appear
        enclosed by u"...", inside a unicode string in the message to sage_server.
        (So there are two u's in the displayed message in the log.)
        Code part of logged input message to sage_server:
          u'code': u'u"\xe1\xe1\xe1"\n'
        Stdout part of logged output message from sage_server:
          "stdout": "u\'\\\\xe1\\\\xe1\\\\xe1\'\\n"
        """
        ustr = 'u"ááá"'
        # same as below: uout = u"u'\\xe1\\xe1\\xe1'\n"
        uout = ustr[2:-1].decode('utf8').__repr__().decode('utf8')
        exec2(ustr, uout)
    def test_unicode_3(self, exec2):
        r"""
        Test for cell with input "ááá".
        Input "ááá" in an actual cell causes utf8 encoding to appear
        inside a unicode string in the message to sage_server.
        Code part of logged input message to sage_server:
          u'code': u'"\xe1\xe1\xe1"\n'
        Stdout part of logged output message from sage_server:
          "stdout": "\'\\\\xc3\\\\xa1\\\\xc3\\\\xa1\\\\xc3\\\\xa1\'\\n"
        """
        ustr = '"ááá"'
        uout = ustr[1:-1].decode('utf8').encode('utf8').__repr__().decode('utf8')
        exec2(ustr, uout)
    def test_unicode_4(self, exec2):
        r"""
        test for cell with input "öäß"
        """
        ustr = '"öäß"'
        uout = ustr[1:-1].decode('utf8').encode('utf8').__repr__().decode('utf8')
        exec2(ustr, uout)

class TestOutputReplace:
    def test_1865(self,exec2):
        code = 'for x in [u"ááá", "ááá"]: print(x)'
        xout = u'ááá\nááá\n'
        exec2(code, xout)

class TestErr:
    def test_non_ascii(self, test_id, sagews):
        # assign x to hbar to trigger non-ascii warning
        code = ("x = " + unichr(295) + "\nx").encode('utf-8')
        m = conftest.message.execute_code(code = code, id = test_id)
        sagews.send_json(m)
        # expect 3 messages from worksheet client, including final done:true
        # 1 stderr Error in lines 1-1
        typ, mesg = sagews.recv()
        assert typ == 'json'
        assert mesg['id'] == test_id
        assert 'stderr' in mesg
        assert 'Error in lines 1-1' in mesg['stderr']
        # 2 stderr WARNING: Code contains non-ascii characters
        typ, mesg = sagews.recv()
        assert typ == 'json'
        assert mesg['id'] == test_id
        assert 'stderr' in mesg
        assert 'WARNING: Code contains non-ascii characters' in mesg['stderr']
        # 3 done
        conftest.recv_til_done(sagews, test_id)
