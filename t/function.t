use strict;
use warnings;

use lib 'lib';

use Test::Most;
use Test::Warnings;
use Test::Deep;

# Fully qualified calls only — white‑box testing
BEGIN { use_ok('Test::Most::Explain') }

#------------------------------------------------------------
# _first_diff_pos
#------------------------------------------------------------
subtest '_first_diff_pos' => sub {

    is(
        Test::Most::Explain::_first_diff_pos('foo', 'foo'),
        -1,
        'identical strings return -1'
    );

    is(
        Test::Most::Explain::_first_diff_pos('foo', 'fob'),
        2,
        'first differing character detected'
    );

    is(
        Test::Most::Explain::_first_diff_pos('foo', 'foobar'),
        3,
        'shorter string mismatch at end'
    );

    is(
        Test::Most::Explain::_first_diff_pos('foobar', 'foo'),
        3,
        'longer string mismatch at end'
    );
};

#------------------------------------------------------------
# _is_deep
#------------------------------------------------------------
subtest '_is_deep' => sub {

    my $raw = '[1,2,3]';

    ok(!Test::Most::Explain::_is_deep('foo'), 'scalar is not deep');

    my $res = Test::Most::Explain::_is_deep($raw);

    ok($res, 'raw array dump is deep');

    ok(Test::Most::Explain::_is_deep('{a=>1}'), 'raw hash dump is deep');
    ok(Test::Most::Explain::_is_deep('bless({}, "X")'), 'blessed ref is deep');

    ok(!Test::Most::Explain::_is_deep("'[1,2,3]'"), 'quoted array dump is NOT deep');
};

#------------------------------------------------------------
# _extract_got_expected
#------------------------------------------------------------
subtest '_extract_got_expected' => sub {

    my @msg = (
        "Failed test 'x'\n",
        "#          got: 'foo'\n",
        "#     expected: 'bar'\n",
    );

    my ($got, $exp) = Test::Most::Explain::_extract_got_expected(@msg);

    is($got, "'foo'", 'got extracted correctly');
    is($exp, "'bar'", 'expected extracted correctly');
};

#------------------------------------------------------------
# _extract_keys
#------------------------------------------------------------
subtest '_extract_keys' => sub {

    my %keys = Test::Most::Explain::_extract_keys("{ 'a' => 1, 'b' => 2 }");

    cmp_deeply(
        \%keys,
        { a => 1, b => 1 },
        'keys extracted from hash dump'
    );
};

done_testing;

