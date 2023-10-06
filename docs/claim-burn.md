## A note on burning at claim-time

In our design, mETH is sent to the contract when the user does an unstake request, but it is not burned (which is what alters the exchange rate) until the request is claimed. This means that the user effectively fixes their rate at unstake time, and any further rewards on that stake are socialized gains for the remaining mETH holders.

As a consequence of burning at this point, it is the case that the delta for the exchange rate adjustment at claim time is slightly accelerated, and this scales with the amount of time between unstaking and claiming.

We have analyzed the effect on the rate and concluded that the difference is entirely negligible in realistic cases. For example, our calculations show that to affect the exchange rate by ~0.7%, a user would have to unstake 20% of the entire TVL in the protocol and wait about 1 year before claiming it.

Given that a user leaving an unclaimed request for a long time is extremely inefficient (they have locked money which is not earning rewards) and the TVL of the protocol is expected to be very large, we consider the likelihood of this affecting the protocol extremely small. In the normal case of a user unstaking a fraction of the TVL and claiming after a few days, the effect is almost immeasurable, so we do not consider this an issue.

For reference, we made this trade-off because it simplifies other parts of the protocol mechanics.
