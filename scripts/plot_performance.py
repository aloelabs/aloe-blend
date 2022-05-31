import json
import math

import numpy as np
import matplotlib.pyplot as plt
import matplotlib.dates as mdates


def percent_change(arr):
    return (arr - arr[0]) / arr[0]


with open('scripts/results/usdc_eth/comparison.json', 'r') as f:
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

    ax1.plot(timestamps, 100 * percent_change(prices[:, 0]), '-k', label='USDC', linewidth='0.5')
    ax1.plot(timestamps, 100 * percent_change(prices[:, 1]), '--k', label='ETH', linewidth='0.5')
    sqrt_price = np.sqrt(prices[:, 0] * prices[:, 1])
    ax1.plot(timestamps, 100 * percent_change(sqrt_price), label=f'sqrt(USDC*ETH)', color='0.8', linewidth='1')

    ax1.plot(timestamps, 100 * percent_change(prices[:, 2]), label=f'Aloe Blend 0.05% Fee', color='teal', linewidth='1')
    # ax1.plot(timestamps, prices[:, 3] / prices[0, 3], label=f'Uniswap V2 0.30% Fee', color='pink', linewidth='1')

    ax1.plot(timestamps, 100 * percent_change(prices[:, 4]), '-b', label=f'Charm Vault 0.30% Fee', linewidth='1')
    ax1.plot(timestamps, 100 * percent_change(prices[:, 5]), '-y', label=f'Gamma Strategies 0.30% Fee', linewidth='1')

    ax1.set_xlabel('Block Timestamp')
    ax1.set_ylabel('Percent Change')
    ax1.legend(loc='upper left', ncol=3, fontsize='x-small')
    ax1.xaxis.set_major_locator(mdates.MonthLocator()) # mdates.WeekdayLocator(byweekday=[mdates.WE])
    ax1.xaxis.set_minor_locator(mdates.WeekdayLocator(byweekday=[mdates.SU]))

    plt.savefig('scripts/results/performance.png', dpi=500)

    print(100 * percent_change(prices[:, 1])[-1])
    print(100 * percent_change(sqrt_price)[-1])
    print(100 * percent_change(prices[:, 2])[-1])
    print(100 * percent_change(prices[:, 4])[-1])
    print(100 * percent_change(prices[:, 5])[-1])

    stacked = np.vstack((
        timestamps.astype('float'),
        100 * percent_change(prices[:, 0]),
        100 * percent_change(prices[:, 1]),
        100 * percent_change(sqrt_price),
        100 * percent_change(prices[:, 2]),
        100 * percent_change(prices[:, 4]),
        100 * percent_change(prices[:, 5]),
    )).T
    np.savetxt('scripts/results/performance.csv', stacked, delimiter=',', header='Timestamp,USDC Price % Δ,ETH Price % Δ,sqrt(USDC*ETH) % Δ,Aloe Blend % Δ,Charm Vault % Δ,Gamma Strategies % Δ')
