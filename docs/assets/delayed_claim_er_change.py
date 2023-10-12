import matplotlib.pyplot as plt
import numpy as np

plt.rcParams['text.usetex'] = True

# e / E_2
xs = np.linspace(0, 0.4, 200)

def f(x, r):
    return  (1 - x)/ (1 - r * x)

# rho_2 / rho_1
rs = np.linspace(0.9, 1.1, 5)

# rho_3 / rho_2
ys = [f(xs, r) for r in rs]

for r, y in zip(rs, ys):
    plt.plot(xs, y, label=f"{r:.2f}")

plt.grid(True)
plt.legend(title='Fractional exchange rate change\nbetween request and claim, ' + r'$\rho_2/\rho_1$', ncol = 2)
plt.xlabel(r'Fraction of total ETH claimed, $e/E_2$')
plt.ylabel(r'Fractional exchange rate change after claim, $\rho_3/\rho_2$')

plt.savefig('delayed_claim_er_change.png', dpi=300)