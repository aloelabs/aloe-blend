import json
import math

import numpy as np
import matplotlib.pyplot as plt
import matplotlib.dates as mdates


with open('scripts/results/performance.json', 'r') as f:
    summaries = json.load(f)

    timestamps = []
    prices = []

    for summary in summaries:
        timestamps.append(np.datetime64(summary['timestamp'], 's'))
        prices.append([
            summary['price0'],
            summary['price1'],
            float(summary['pricePerShareBlend']),
            float(summary['pricePerShareV2']),
            float(summary.get('pricePerShareCharm', 1)),
            float(summary.get('pricePerShareVisor', 1)),
        ])

    timestamps = np.array(timestamps)
    prices = np.array(prices)

    fig, ax1 = plt.subplots(1, 1)

    ax1.plot(timestamps, prices[:, 0] / prices[0, 0], '-k', label='USDC', linewidth='0.5')
    ax1.plot(timestamps, prices[:, 1] / prices[0, 1], '--k', label='ETH', linewidth='0.5')
    ax1.plot(timestamps, np.sqrt(prices[:, 0] * prices[:, 1]) / np.sqrt(prices[0, 0] * prices[0, 1]), label=f'sqrt(USDC*ETH)', color='0.8', linewidth='1')

    ax1.plot(timestamps, prices[:, 2] / prices[0, 2], label=f'Aloe Blend 0.05% Fee', color='teal', linewidth='1')
    ax1.plot(timestamps, prices[:, 3] / prices[0, 3], label=f'Uniswap V2 0.30% Fee', color='pink', linewidth='1')

    ax1.plot(timestamps, prices[:, 4] / prices[0, 4], '-b', label=f'Charm Vault 0.30% Fee', linewidth='1')
    ax1.plot(timestamps, prices[:, 5] / prices[0, 5], '-y', label=f'Gamma Strategies 0.30% Fee', linewidth='1')

    ax1.set_xlabel('Block Timestamp')
    ax1.set_ylabel('Price (normalized)')
    ax1.legend(loc='upper left', ncol=3, fontsize='x-small')
    ax1.xaxis.set_major_locator(mdates.WeekdayLocator(byweekday=mdates.SU))
    ax1.xaxis.set_minor_locator(mdates.DayLocator())

    plt.savefig('scripts/results/performance.png', dpi=200)
