#!/usr/bin/env python3
from collections import defaultdict

import matplotlib.pyplot as plt
import numpy as np
import yaml


LIB_NAMES = {
    'decode': {
        'lunajson': ("lunajson decoder", 'C0'),
        'lunajson_sax': ("lunajson SAX", 'C1'),
        'dkjson_pure': ("dkjson w/o lpeg", 'C2'),
        'dkjson_lpeg': ("dkjson with lpeg", 'C3'),
        'cjson': ("Lua CJSON", 'C4'),
    },
    'encode': {
        'lunajson': ("lunajson", 'C0'),
        'dkjson': ("dkjson", 'C2'),
        'cjson': ("Lua CJSON", 'C4'),
    },
}


def load_result(f):
    lua_impls = []
    colors = {}
    data_dict = defaultdict(lambda: defaultdict(list))

    for lua_result in yaml.safe_load_all(f):
        lua_impls.append(lua_result['lua_impl'])
        for op in ('decode', 'encode'):
            for lib, lib_result in lua_result[op].items():
                libname, color = LIB_NAMES[op][lib]
                colors[libname] = color
                for task, time in lib_result.items():
                    filename = op + '-' + task
                    data_dict[filename][libname].append(time)

    return lua_impls, colors, data_dict


def plot_data(filename, lua_impls, colors, data):
    dpi = 96
    fig, ax = plt.subplots(figsize=(800/dpi, 400/dpi))
    plt.style.use('tableau-colorblind10')

    if 'decode' in filename:
        ax.set_title("Decoding Performances")
    else:
        ax.set_title("Encoding Performances")
    ax.set_ylabel("Elapsed Time in Seconds")

    ax.set_axisbelow(True)
    xticks = np.arange(len(lua_impls))
    ax.set_xticks(xticks)
    ax.set_xticklabels(lua_impls)
    ax.grid(True, axis='y', linestyle='dashed')

    groupwidth = 0.75
    for i, (libname, times) in enumerate(data.items()):
        barcenter = (i - 0.5 * (len(data) - 1)) * groupwidth / len(data)
        barwidth = groupwidth / len(data)
        ax.bar(xticks + barcenter, times,
               color=colors[libname], width=barwidth, label=libname)

    ax.legend()
    fig.tight_layout()
    plt.savefig(filename + '.png', dpi=dpi)


def main():
    import matplotlib as mpl
    mpl.use('Agg')

    with open('bench_result.yml') as f:
        lua_impls, colors, data_dict = load_result(f)
        for filename, data in data_dict.items():
            plot_data(filename, lua_impls, colors, data)


if __name__ == '__main__':
    main()
