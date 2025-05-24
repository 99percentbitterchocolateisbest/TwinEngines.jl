```
TwinEngines/
├── Project.toml
├── Manifest.toml
├── README.md
├── src/
│   ├── TwinEngines.jl                 # Main module file
│   ├── core/                        # Core infrastructure
│   │   ├── exchange.jl             # MainExchange, SubExchange
│   │   ├── instrument.jl           # AbstractInstrument, Bond, Equity, etc.
│   │   ├── orderbook.jl            # Limit order book, matching engine
│   │   ├── order.jl                # Order types (limit, market, cancel, etc.)
│   │   └── events.jl               # Market events, time management
│   ├── agents/                     # Agents and strategies
│   │   ├── abstract_agent.jl       # Base agent type
│   │   ├── market_maker.jl
│   │   ├── investor.jl
│   │   ├── arbitrageur.jl
│   │   └── strategy_utils.jl       # Helper functions for agent behavior
│   ├── simulation/                 # Simulation runtime
│   │   ├── clock.jl                # Time handling (event-driven or discrete)
│   │   ├── runner.jl               # Main simulation loop
│   │   └── metrics.jl              # PnL, slippage, liquidity tracking
│   ├── pricing/                    # Optional: pricing and analytics
│   │   ├── bond_pricing.jl         # Yield, duration, spread, etc.
│   │   └── equity_valuation.jl     # P/E, DDM, etc.
│   └── utils/                      # Misc utilities
│       ├── logger.jl
│       ├── config.jl
│       └── data_export.jl          # CSV/json logging of trades, books
├── test/
│   ├── runtests.jl
│   ├── test_orderbook.jl
│   ├── test_exchange.jl
│   ├── test_agents.jl
│   └── test_simulation.jl
└── examples/
    ├── basic_bond_sim.jl
    ├── fragmented_liquidity.jl
    └── stress_test_regulation.jl
```
