from multiprocessing import Pool

import requests


def f(x):
    while True:
        response = requests.get("https://foo-ecs.ci-cd.infrahouse.com/")
        print(response.text)
        assert response.status_code == 200


if __name__ == '__main__':
    with Pool(20) as p:
        print(
            p.map(f, [1] * 100)
        )
