// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./UINT512.sol";

library Equations {
    using UINT512Math for UINT512;

    /// @dev Computes both raw (LS0, MS0) and weighted (LS1, MS1) squared bounds for a proposal
    function eqn0(
        uint80 stake,
        uint176 lower,
        uint176 upper
    )
        internal
        pure
        returns (
            uint256 LS0,
            uint256 MS0,
            uint256 LS1,
            uint256 MS1
        )
    {
        unchecked {
            // square each bound
            (LS0, MS0) = FullMath.square512(lower);
            (LS1, MS1) = FullMath.square512(upper);
            // add squared bounds together
            LS0 = (LS0 >> 1) + (LS1 >> 1);
            (LS0, LS1) = FullMath.mul512(LS0, 2); // LS1 is now a carry bit
            MS0 += MS1 + LS1;
            // multiply by stake
            (LS1, MS1) = FullMath.mul512(LS0, stake);
            MS1 += MS0 * stake;
        }
    }

    /**
     * @notice A complicated equation used when computing rewards.
     * @param a One of `sumOfSquaredBounds` | `sumOfSquaredBoundsWeighted`
     * @param b One of `sumOfLowerBounds`   | `sumOfLowerBoundsWeighted`
     * @param c: One of `sumOfUpperBounds`  | `sumOfUpperBoundsWeighted`
     * @param d: One of `proposalCount`     | `stakeTotal`
     * @param lowerTrue: `groundTruth.lower`
     * @param upperTrue: `groundTruth.upper`
     * @return Output of Equation 1 from the whitepaper
     */
    function eqn1(
        UINT512 memory a,
        uint256 b,
        uint256 c,
        uint256 d,
        uint256 lowerTrue,
        uint256 upperTrue
    ) internal pure returns (UINT512 memory) {
        UINT512 memory temp;

        (temp.LS, temp.MS) = FullMath.mul512(d * lowerTrue, lowerTrue);
        (a.LS, a.MS) = a.add(temp.LS, temp.MS);

        (temp.LS, temp.MS) = FullMath.mul512(d * upperTrue, upperTrue);
        (a.LS, a.MS) = a.add(temp.LS, temp.MS);

        (temp.LS, temp.MS) = FullMath.mul512(b, lowerTrue << 1);
        (a.LS, a.MS) = a.sub(temp.LS, temp.MS);

        (temp.LS, temp.MS) = FullMath.mul512(c, upperTrue << 1);
        (a.LS, a.MS) = a.sub(temp.LS, temp.MS);

        return a;
    }
}
