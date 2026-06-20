import functools

import pytest

import util


def pytest_addoption(parser):
    parser.addoption("--entrypoint", action="store", required=True)
    parser.addoption("--cluster", action="store", required=True)
    parser.addoption("--secret", action="store", required=True)


def pytest_generate_tests(metafunc):
    for opt in ['entrypoint', 'cluster', 'secret']:
        if opt in metafunc.fixturenames:
            metafunc.parametrize(opt, [metafunc.config.getoption(opt)], scope='session')


@pytest.fixture(scope='session')
def call(request):
    options = request.config.option
    return functools.partial(
            util.api_call,
            options.entrypoint,
            options.cluster,
            options.secret,
            log_func=print,
    )


@pytest.fixture(scope='module')
def pool(call, cluster):
    pool_uuid = call('POST', '/pool', data={'name': 'poolX', 'cluster_id': cluster, 'no_secret': True})
    yield pool_uuid
    call('DELETE', f'/pool/{pool_uuid}')


@pytest.fixture(scope='module')
def lvol(call, cluster, pool):
    pool_name = call('GET', f'/pool/{pool}')[0]['pool_name']
    lvol_uuid = call('POST', '/lvol', data={
        'name': 'lvolX',
        'size': '1G',
        'pool': pool_name}
    )
    yield lvol_uuid
    call('DELETE', f'/lvol/{lvol_uuid}')
    util.await_deletion(call, f'/lvol/{lvol_uuid}')
