import json
import math

import numpy as np
import matplotlib.pyplot as plt
import matplotlib.dates as mdates


def percent_change(arr):
    return (arr - arr[0]) / arr[0]

def smooth(y, box_pts):
    box = np.ones(box_pts)/box_pts
    y_smooth = np.convolve(y, box, mode='same')
    return y_smooth


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
        ])

    timestamps = np.array(timestamps)
    prices = np.array(prices)

    pricePerShare = prices[:, 2]
    perf = np.roll(pricePerShare, shift=-1) / pricePerShare - 1.0
    
    year = 365 * 24 * 60 * 60
    seconds = timestamps.astype('float')
    deltaT = np.roll(seconds, shift=-1) - seconds

    gAPR = year * perf[:-1] / deltaT[:-1]
    print(gAPR.mean())

    fig, ax1 = plt.subplots(1, 1)
    ax1.plot(timestamps[:-1], 100 * gAPR)
    ax1.plot(timestamps[:-1], 100 * smooth(gAPR, 5))

    ax1.set_xlabel('Date where 48-hour sliding measurement window ends')
    ax1.set_ylabel('gAPR [%]')
    ax1.xaxis.set_major_locator(mdates.MonthLocator()) # mdates.WeekdayLocator(byweekday=[mdates.WE])
    ax1.xaxis.set_minor_locator(mdates.WeekdayLocator(byweekday=[mdates.SU]))

    plt.savefig('scripts/results/performance.png', dpi=500)
