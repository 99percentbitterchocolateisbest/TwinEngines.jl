using DataStructures
using UUIDs

"""
    OrderSide

Enum representing the side of an order (buy or sell).
"""
@enum OrderSide BUY SELL

"""
    OrderType

Enum representing different types of orders.
"""
@enum OrderType LIMIT MARKET IOC FOK

"""
    Order

Represents a trading order in the system.
"""
mutable struct Order
    id::UUID
    instrument_id::String
    side::OrderSide
    order_type::OrderType
    quantity::Int64
    price::Float64  # ignore for market orders
    timestamp::Float64
    agent_id::String
    remaining_quantity::Int64
    
    function Order(instrument_id::String, side::OrderSide, order_type::OrderType, 
                   quantity::Int64, price::Float64, timestamp::Float64, agent_id::String)
        new(uuid4(), instrument_id, side, order_type, quantity, price, timestamp, 
            agent_id, quantity)
    end
end

"""
    Trade

Represents an executed trade between two orders.
"""
struct Trade
    id::UUID
    instrument_id::String
    buy_order_id::UUID
    sell_order_id::UUID
    price::Float64
    quantity::Int64
    timestamp::Float64
    buy_agent_id::String
    sell_agent_id::String
    
    function Trade(instrument_id::String, buy_order::Order, sell_order::Order, 
                   price::Float64, quantity::Int64, timestamp::Float64)
        new(uuid4(), instrument_id, buy_order.id, sell_order.id, price, quantity, 
            timestamp, buy_order.agent_id, sell_order.agent_id)
    end
end

"""
    PriceLevel

Represents a price level in the order book with a queue of orders.
"""
mutable struct PriceLevel
    price::Float64
    orders::Queue{Order}
    total_quantity::Int64
    
    PriceLevel(price::Float64) = new(price, Queue{Order}(), 0)
end

"""
    OrderBook

Limit order book with price-time priority matching engine.
"""
mutable struct OrderBook
    instrument_id::String
    bids::SortedDict{Float64, PriceLevel}  # highest first
    asks::SortedDict{Float64, PriceLevel}  # lowest first
    order_map::Dict{UUID, Order}  # for fast order lookup
    trades::Vector{Trade}
    last_trade_price::Float64
    last_trade_time::Float64
    
    function OrderBook(instrument_id::String)
        new(instrument_id,
            SortedDict{Float64, PriceLevel}(Base.Order.Reverse),  # high to low
            SortedDict{Float64, PriceLevel}(),                     # low to high
            Dict{UUID, Order}(),
            Vector{Trade}(),
            0.0,
            0.0)
    end
end

"""
    add_order!(book::OrderBook, order::Order, current_time::Float64)

Add an order to the order book and attempt to match it.
Returns a vector of resulting trades.
"""
function add_order!(book::OrderBook, order::Order, current_time::Float64)::Vector{Trade}
    trades = Trade[]
    
    # Handle market orders and aggressive limit orders
    if order.order_type == MARKET || is_aggressive_order(book, order)
        trades = match_order!(book, order, current_time)
    end
    
    # Add remaining quantity to book if any
    if order.remaining_quantity > 0 && order.order_type != IOC
        add_to_book!(book, order)
    end
    
    return trades
end

"""
    match_order!(book::OrderBook, order::Order, current_time::Float64)

Attempt to match an incoming order against existing orders in the book.
"""
function match_order!(book::OrderBook, order::Order, current_time::Float64)::Vector{Trade}
    trades = Trade[]
    
    if order.side == BUY
        # Match against asks 
        while order.remaining_quantity > 0 && !isempty(book.asks)
            best_ask_price = first(book.asks).first
            
            # Check if can match
            if order.order_type == MARKET || order.price >= best_ask_price
                trade = execute_trade!(book, order, book.asks[best_ask_price], 
                                     best_ask_price, current_time)
                if trade !== nothing
                    push!(trades, trade)
                    push!(book.trades, trade)
                end
            else
                break  # No possible matches 
            end
        end
    else  # SELL
        # Match against bids 
        while order.remaining_quantity > 0 && !isempty(book.bids)
            best_bid_price = first(book.bids).first
            
            # Check if can match
            if order.order_type == MARKET || order.price <= best_bid_price
                trade = execute_trade!(book, order, book.bids[best_bid_price], 
                                     best_bid_price, current_time)
                if trade !== nothing
                    push!(trades, trade)
                    push!(book.trades, trade)
                end
            else
                break  # No possible matches 
            end
        end
    end
    
    return trades
end

"""
    execute_trade!(book::OrderBook, incoming_order::Order, price_level::PriceLevel, 
                   trade_price::Float64, current_time::Float64)

Execute a trade between an incoming order and the first order at a price level.
"""
function execute_trade!(book::OrderBook, incoming_order::Order, price_level::PriceLevel, 
                       trade_price::Float64, current_time::Float64)::Union{Trade, Nothing}
    if isempty(price_level.orders)
        return nothing
    end
    
    resting_order = first(price_level.orders)
    trade_quantity = min(incoming_order.remaining_quantity, resting_order.remaining_quantity)
    
    # Create trade
    if incoming_order.side == BUY
        trade = Trade(book.instrument_id, incoming_order, resting_order, 
                     trade_price, trade_quantity, current_time)
    else
        trade = Trade(book.instrument_id, resting_order, incoming_order, 
                     trade_price, trade_quantity, current_time)
    end
    
    # Update order quantities
    incoming_order.remaining_quantity -= trade_quantity
    resting_order.remaining_quantity -= trade_quantity
    price_level.total_quantity -= trade_quantity
    
    # Remove resting order if fully filled
    if resting_order.remaining_quantity == 0
        dequeue!(price_level.orders)
        delete!(book.order_map, resting_order.id)
        
        # Remove price level if empty
        if isempty(price_level.orders)
            if incoming_order.side == BUY
                delete!(book.asks, trade_price)
            else
                delete!(book.bids, trade_price)
            end
        end
    end
    
    # Update last trade info
    book.last_trade_price = trade_price
    book.last_trade_time = current_time
    
    return trade
end

"""
    add_to_book!(book::OrderBook, order::Order)

Add an order to the appropriate side of the book.
"""
function add_to_book!(book::OrderBook, order::Order)
    if order.remaining_quantity <= 0
        return
    end
    
    side_book = order.side == BUY ? book.bids : book.asks
    
    # Get or create price level
    if haskey(side_book, order.price)
        price_level = side_book[order.price]
    else
        price_level = PriceLevel(order.price)
        side_book[order.price] = price_level
    end
    
    # Add order to price level
    enqueue!(price_level.orders, order)
    price_level.total_quantity += order.remaining_quantity
    book.order_map[order.id] = order
end

"""
    cancel_order!(book::OrderBook, order_id::UUID)

Cancel an order in the book.
"""
function cancel_order!(book::OrderBook, order_id::UUID)::Bool
    if !haskey(book.order_map, order_id)
        return false
    end
    
    order = book.order_map[order_id]
    side_book = order.side == BUY ? book.bids : book.asks
    
    if !haskey(side_book, order.price)
        return false
    end
    
    price_level = side_book[order.price]
    
    # Find and remove order from queue (inefficient?)
    temp_orders = Order[]
    found = false
    
    while !isempty(price_level.orders)
        current_order = dequeue!(price_level.orders)
        if current_order.id == order_id
            found = true
            price_level.total_quantity -= current_order.remaining_quantity
        else
            push!(temp_orders, current_order)
        end
    end
    
    for temp_order in temp_orders
        enqueue!(price_level.orders, temp_order)
    end
    
    if isempty(price_level.orders)
        delete!(side_book, order.price)
    end
    
    if found
        delete!(book.order_map, order_id)
    end
    
    return found
end

"""
    is_aggressive_order(book::OrderBook, order::Order)

Check if a limit order would immediately match against existing orders.
"""
function is_aggressive_order(book::OrderBook, order::Order)::Bool
    if order.order_type != LIMIT
        return false
    end
    
    if order.side == BUY && !isempty(book.asks)
        return order.price >= first(book.asks).first
    elseif order.side == SELL && !isempty(book.bids)
        return order.price <= first(book.bids).first
    end
    
    return false
end

"""
    get_best_bid(book::OrderBook)

Get the best bid price and quantity.
"""
function get_best_bid(book::OrderBook)::Union{Tuple{Float64, Int64}, Nothing}
    if isempty(book.bids)
        return nothing
    end
    
    price, level = first(book.bids)
    return (price, level.total_quantity)
end

"""
    get_best_ask(book::OrderBook)

Get the best ask price and quantity.
"""
function get_best_ask(book::OrderBook)::Union{Tuple{Float64, Int64}, Nothing}
    if isempty(book.asks)
        return nothing
    end
    
    price, level = first(book.asks)
    return (price, level.total_quantity)
end

"""
    get_spread(book::OrderBook)

Get the bid-ask spread.
"""
function get_spread(book::OrderBook)::Union{Float64, Nothing}
    best_bid = get_best_bid(book)
    best_ask = get_best_ask(book)
    
    if best_bid === nothing || best_ask === nothing
        return nothing
    end
    
    return best_ask[1] - best_bid[1]
end

"""
    get_mid_price(book::OrderBook)

Get the mid-market price.
"""
function get_mid_price(book::OrderBook)::Union{Float64, Nothing}
    best_bid = get_best_bid(book)
    best_ask = get_best_ask(book)
    
    if best_bid === nothing || best_ask === nothing
        return nothing
    end
    
    return (best_bid[1] + best_ask[1]) / 2.0
end

"""
    get_market_depth(book::OrderBook, levels::Int=5)

Get market depth for specified number of levels on each side.
"""
function get_market_depth(book::OrderBook, levels::Int=5)::NamedTuple
    bid_levels = []
    ask_levels = []
    
    # Get bid levels
    count = 0
    for (price, level) in book.bids
        if count >= levels
            break
        end
        push!(bid_levels, (price=price, quantity=level.total_quantity))
        count += 1
    end
    
    # Get ask levels
    count = 0
    for (price, level) in book.asks
        if count >= levels
            break
        end
        push!(ask_levels, (price=price, quantity=level.total_quantity))
        count += 1
    end
    
    return (bids=bid_levels, asks=ask_levels)
end