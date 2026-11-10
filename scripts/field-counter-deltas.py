#!/usr/bin/env python3
"""Convert GhostWave field samples into per-node counter changes."""
import argparse
import csv
import json
import sys
from pathlib import Path

COUNTERS = ('tx', 'rx', 'delivered')


def changes(report):
    if report.get('version') != 1 or not isinstance(report.get('samples'), list):
        raise ValueError('Expected a version 1 GhostWave field report')
    previous = {}
    for sample in report['samples']:
        node = sample['node']
        if type(node) is not int:
            raise ValueError('Missing numeric node identity')
        values = tuple(int(sample[k]) for k in COUNTERS)
        if min(values) < 0:
            raise ValueError('Negative counter')
        old = previous.get(node)
        uptime = sample.get('uptimeSeconds')
        firmware = sample.get('firmware')
        previous[node] = (values, uptime, firmware)
        if old is None:
            yield (sample['at'], node, 'baseline', '', '', '')
            continue
        counters, last_uptime, last_firmware = old
        delta = tuple(a - b for a, b in zip(values, counters))
        restarted = uptime is not None and last_uptime is not None and uptime < last_uptime
        if restarted or min(delta) < 0 or firmware != last_firmware:
            yield (sample['at'], node, 'new baseline', '', '', '')
        else:
            yield (sample['at'], node, 'interval', *delta)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('report', type=Path)
    args = parser.parse_args()
    try:
        rows = list(changes(json.loads(args.report.read_text())))
    except (OSError, KeyError, TypeError, ValueError) as error:
        parser.exit(1, f'Invalid field report: {error}\n')
    writer = csv.writer(sys.stdout)
    writer.writerow(('at', 'node', 'interval_type', 'tx_delta', 'rx_delta', 'delivered_delta'))
    writer.writerows(rows)
