//+------------------------------------------------------------------+
//|                                                         ZZPA.mq5 |
//|                                         Copyright 2020, Quang Vu |
//|                                        https://www.traderfoo.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2020, Quang Vu"
#property link      "https://www.traderfoo.com"
#property version   "1.00"
#include <Trade\PositionInfo.mqh>
#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>  
#include <Trade\AccountInfo.mqh>
#include <Trade\DealInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include <Expert\Money\MoneyFixedMargin.mqh>
CPositionInfo               m_position;                                 // trade position object
CTrade                      m_trade;                                    // trading object
CSymbolInfo                 m_symbol;                                   // symbol info object
CAccountInfo                m_account;                                  // account info wrapper
CDealInfo                   m_deal;                                     // deals object
COrderInfo                  m_order;                                    // pending orders object
CMoneyFixedMargin           *m_money;                                   // money management object
//---
enum ENUM_LOT_OR_RISK{
                            lot                       = 0,                 // Constant lot
                            risk                      = 1,                 // Risk in percent for a deal
};
enum ENUM_POS_OPEN_MODE{
                            follow                    = 0,                 // Follow
                            reverse                   = 1,                 // Reverse                            
};
enum ENUM_DAYOFWEEK{ 
                            all                       = 7,                 // ALL
                            mo                        = 1,                 // MONDAY
                            tu                        = 2,                 // TUESDAY
                            we                        = 3,                 // WEDNESDAY
                            th                        = 4,                 // THURSDAY
                            fr                        = 5,                 // FRIDAY
   
};
//--- input parameters
input group                 "System Settings" 
input string                InpTimeStart              = "01:00:00";        // Time start
input string                InpTimeStop               = "23:00:00";        // Time stop
input ulong                 InpMagic                  = 88888888;          // Magic number
//---
input group                 "Trading Settings";
input ushort                InpBalancePercent         = 10;                // Balance stop percents (0 = No Stop)
input ENUM_POS_OPEN_MODE    InpPositionOpenMode       = follow;            // Position Open Mode
input double                InpSpreadLimit            = 100;               // Spread Limit (in points)
input ulong                 InpSlippageLimit          = 25;                // Slippage Limit(in points)
//---
input group                 "Volume Settings" 
input ENUM_LOT_OR_RISK      IntLotOrRisk              = risk;              // Money management: LOT or RISK
input double                InpVolumeLorOrRisk        = 1;                 // The value for "Money management"
//---
input group                 "SLTP Settings" 
input ushort                InpStopLoss               = 50;                // Stop Loss (in pips)
input ushort                InpTakeProfit             = 50;                // Take Profit (in pips)
//---
input group                 "Trailing-Stop Settings" 
input ushort                InpTrailingStop           = 0;                 // Trailing Stop (in pips. 0 = No trailing)
input ushort                InpTrailingStep           = 10;                // Trailing Step (in pips)
//---
input group                 "ZigZag Info Settings";
input int                   InpZigZagDepth            = 12;                // Depth
input int                   InpZigZagDeviation        = 5;                 // Deviation
input int                   InpZigZagBackStep         = 8;                 // Backstep
input color                 InpZigZagColor            = clrBlue;           // Color
input int                   InpZigZagWidth            = 3;                 // Width
input bool                  InpZigZagDisplay          = true;              // Display ZZ on chart
//---
input group                 "ZigZag Trading Settings"
input int                   InpZZPeriodRangerMin      = 5;                  // Period Ranger Min
input int                   InpZZPeriodRangerMax      = 50;                 // Period Ranger Max
input double                InpZZPipsRangerMin        = 5;                  // Pips Ranger Min (in pips)                     
input double                InpZZPipsRangerMax        = 20;                 // Pips Ranger Max (in pips)
input double                InpFiboOpenPositionLevel  = 5;                  // Fibo Level Open Position

input group                 "Open Position Settings";
input ENUM_DAYOFWEEK        InpDayOfWeek              = all;               // Day of week
input string                InpHoursString            = "9,10,11,12,15,16,17,18";   // Hours String
input int                   InpMinuteMin              = 5;                 // Minute Min Open Position
input int                   InpMinuteMax              = 10;                // Minute Max Open Position
//---
input group                 "Fibo Settings"
input bool                  InpFiboDisplay            = true;              // Display Fibo on chart
input color                 InpFiboColor              = clrYellow;         // Color
//---
input group                 "Indicator RSI"
input int                   InpRSIPeriod              = 12;                // RSI period
input ENUM_APPLIED_PRICE    InpRSIApplied_Price       = PRICE_TYPICAL;     // RSI applied price 
input int                   InpRSIValueCheckForBuy    = 20;                // RSI Value Check For Buy (<=)
input int                   InpRSIValueCheckForSell   = 80;                // RSI Value Check For Sell (>=)
//---
double                      ExtStopLoss               = 0.0;
double                      ExtTakeProfit             = 0.0;
double                      ExtTrailingStop           = 0.0;
double                      ExtTrailingStep           = 0.0;
double                      ExtBalanceTP              = 0.0;
double                      ExtBalanceSL              = 0.0;
double                      ExtDistancePriceOpen      = 0.0;
//---
double                      m_adjusted_point;                              // point value adjusted for 3 or 5 points
//---
bool                        m_need_open_buy           = false;
bool                        m_need_open_sell          = false;
bool                        m_waiting_transaction     = false;             // "true" -> it's forbidden to trade, we expect a transaction
ulong                       m_waiting_order_ticket    = 0;                 // ticket of the expected order
bool                        m_transaction_confirmed   = false;             // "true" -> transaction confirmed
bool                        trading                   = true;
//---
MqlRates                    rates[];
int                         zigzag_handler;
double                      zigzag_array[2];
datetime                    zigzag_time[2];
double                      zigzag_a;
double                      zigzag_b;
datetime                    zigzag_time_a;
datetime                    zigzag_time_b;
int                         rsi_handler;
double                      rsi_array[]; 
string                      hours_array[];
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    //---
    if (InpTrailingStop != 0 && InpTrailingStep == 0) {
        string err_text = "Trailing is not possible: parameter \"Trailing Step\" is zero!";
        //--- when testing, we will only output to the log about incorrect input parameters
        if (MQLInfoInteger(MQL_TESTER)) {
            Print(__FUNCTION__, ", ERROR: ", err_text);
            return (INIT_FAILED);
        } else // if the Expert Advisor is run on the chart, tell the user about the error
        {
            Alert(__FUNCTION__, ", ERROR: ", err_text);
            return (INIT_PARAMETERS_INCORRECT);
        }
    }
    //---
    if (!m_symbol.Name(Symbol())) // sets symbol name
        return (INIT_FAILED);
    RefreshRates();
    //---
    m_trade.SetExpertMagicNumber(InpMagic);
    m_trade.SetMarginMode();
    m_trade.SetTypeFillingBySymbol(m_symbol.Name());
    m_trade.SetDeviationInPoints(InpSlippageLimit);
    //--- tuning for 3 or 5 digits
    int digits_adjust = 1;
    if (m_symbol.Digits() == 3 || m_symbol.Digits() == 5)
        digits_adjust = 10;
    m_adjusted_point = m_symbol.Point() * digits_adjust;

    ExtStopLoss = InpStopLoss * m_adjusted_point;
    ExtTakeProfit = InpTakeProfit * m_adjusted_point;
    ExtTrailingStop = InpTrailingStop * m_adjusted_point;
    ExtTrailingStep = InpTrailingStep * m_adjusted_point;
    
    
    //---
    ExtBalanceTP = m_account.Balance() + (m_account.Balance() * InpBalancePercent/100);
    ExtBalanceSL = m_account.Balance() - (m_account.Balance() * InpBalancePercent/100);
    //---   
    
    //--- check the input parameter "Lots"
    string err_text = "";
    if (IntLotOrRisk == lot) {
        if (!CheckVolumeValue(InpVolumeLorOrRisk, err_text)) {
            //--- when testing, we will only output to the log about incorrect input parameters
            if (MQLInfoInteger(MQL_TESTER)) {
                Print(__FUNCTION__, ", ERROR: ", err_text);
                return (INIT_FAILED);
            } else // if the Expert Advisor is run on the chart, tell the user about the error
            {
                Alert(__FUNCTION__, ", ERROR: ", err_text);
                return (INIT_PARAMETERS_INCORRECT);
            }
        }
    } else {
        if (m_money != NULL)
            delete m_money;
        m_money = new CMoneyFixedMargin;
        if (m_money != NULL) {
            if (!m_money.Init(GetPointer(m_symbol), Period(), m_symbol.Point() * digits_adjust))
                return (INIT_FAILED);
            m_money.Percent(InpVolumeLorOrRisk);
        } else {
            Print(__FUNCTION__, ", ERROR: Object CMoneyFixedMargin is NULL");
            return (INIT_FAILED);
        }
    }
    //---
    if(!InitZigZag()){
      return INIT_FAILED;
    } 
    if(!InitRSI()){
      return INIT_FAILED;
    } 
    InitHoursArray();
    Print(hours_array[0] );
    return (INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//|  Init                                                            |
//+------------------------------------------------------------------+
bool InitRSI() {
    rsi_handler  = iRSI(m_symbol.Name(),Period(),InpRSIPeriod,InpRSIApplied_Price);
    if(rsi_handler != NULL){
      return (true);
    }
    return false;
}

bool InitZigZag() {
    zigzag_handler  = iCustom(m_symbol.Name(),Period(),"Examples/ZigZag", InpZigZagDepth, InpZigZagDeviation, InpZigZagBackStep);
    if(zigzag_handler != NULL){        
        return true;      
    }else {       
        return false;   
    }
}

void InitHoursArray() {
    string sep=",";                // A separator as a character 
    ushort u_sep;                  // The code of the separator character 
    u_sep=StringGetCharacter(sep,0); 
    //--- Split the string to substrings 
    int k=StringSplit(InpHoursString,u_sep,hours_array); 
}
bool InitZigZagHighLowArray(double & array[], datetime & time[]){
   double high_low_array[];
   int start_pos = 0, count = 500;
   int CopyNumber = CopyBuffer(zigzag_handler, 0, start_pos, count, high_low_array);  
      
   if(CopyNumber > 0) {
      ArraySetAsSeries(high_low_array, true);
      ArraySetAsSeries(rates, true);
      if(CopyRates(m_symbol.Name(), Period(), start_pos, count, rates) > 0){   
         int counter = 0;
         for(int i = 0; i <= CopyNumber && counter < ArraySize(array) && !IsStopped(); i++){
            if(high_low_array[i] != 0.0){
               array[counter] = high_low_array[i];
               time[counter] = rates[i].time;              
               counter++;               
            }
         }
      }      
      return true;
   }else {
       Print("Indicator Bufer Unavailable");
       return false;
   }
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    //---
    if (m_money != NULL)
        delete m_money;
}
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
   if(checktime(starttime(), endtime())) {
      //Print("trading...");
      //--- Check Balance Stop Trading
      if(CheckBalanceStop()){
         CloseAllPositions();
         trading = false;      
      }  
      //---      
      if(trading){  
         if(CheckDayOfWeek()){       
            if(CheckTimeHourOpenPos()){ 
               if(CheckTimeMinuteOpenPos()){              
                  Trade();
               }
            }        
         }
      }
   }
}
//+------------------------------------------------------------------+
//| TradeTransaction function                                        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction & trans,const MqlTradeRequest & request,const MqlTradeResult & result) {  
    //--- get transaction type as enumeration value
    ENUM_TRADE_TRANSACTION_TYPE type = trans.type;
    //--- if transaction is result of addition of the transaction in history
    if (type == TRADE_TRANSACTION_DEAL_ADD) {
        long deal_ticket = 0;
        long deal_order = 0;
        long deal_time = 0;
        long deal_time_msc = 0;
        long deal_type = -1;
        long deal_entry = -1;
        long deal_magic = 0;
        long deal_reason = -1;
        long deal_position_id = 0;
        double deal_volume = 0.0;
        double deal_price = 0.0;
        double deal_commission = 0.0;
        double deal_swap = 0.0;
        double deal_profit = 0.0;
        string deal_symbol = "";
        string deal_comment = "";
        string deal_external_id = "";
        if (HistoryDealSelect(trans.deal)) {
            deal_ticket = HistoryDealGetInteger(trans.deal, DEAL_TICKET);
            deal_order = HistoryDealGetInteger(trans.deal, DEAL_ORDER);
            deal_time = HistoryDealGetInteger(trans.deal, DEAL_TIME);
            deal_time_msc = HistoryDealGetInteger(trans.deal, DEAL_TIME_MSC);
            deal_type = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
            deal_entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
            deal_magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
            deal_reason = HistoryDealGetInteger(trans.deal, DEAL_REASON);
            deal_position_id = HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);

            deal_volume = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
            deal_price = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
            deal_commission = HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
            deal_swap = HistoryDealGetDouble(trans.deal, DEAL_SWAP);
            deal_profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);

            deal_symbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
            deal_comment = HistoryDealGetString(trans.deal, DEAL_COMMENT);
            deal_external_id = HistoryDealGetString(trans.deal, DEAL_EXTERNAL_ID);
        } else {
            return;
        }
        
        if (deal_symbol == m_symbol.Name() && deal_magic == InpMagic){
            if (deal_entry == DEAL_ENTRY_IN){
                if (deal_type == DEAL_TYPE_BUY || deal_type == DEAL_TYPE_SELL) {
                    if (m_waiting_transaction){
                        if (m_waiting_order_ticket == deal_order) {
                            Print(__FUNCTION__, " Transaction confirmed");
                            m_transaction_confirmed = true;
                        }
                    }
                }
            }
         }
    }
}
//+------------------------------------------------------------------+
//| Refreshes the symbol quotes data                                 |
//+------------------------------------------------------------------+
bool RefreshRates(void) {
    //--- refresh rates
    if (!m_symbol.RefreshRates()) {
        Print("RefreshRates error");
        return (false);
    }
    //--- protection against the return value of "zero"
    if (m_symbol.Ask() == 0 || m_symbol.Bid() == 0)
        return (false);
    //---
    return (true);
}
//+------------------------------------------------------------------+
//| Check the correctness of the position volume                     |
//+------------------------------------------------------------------+
bool CheckVolumeValue(double volume, string & error_description) {
    //--- minimal allowed volume for trade operations
    double min_volume = m_symbol.LotsMin();
    if (volume < min_volume) {
        error_description = StringFormat("Volume is less than the minimal allowed SYMBOL_VOLUME_MIN=%.2f", min_volume);
        return (false);
    }
    //--- maximal allowed volume of trade operations
    double max_volume = m_symbol.LotsMax();
    if (volume > max_volume) {
        error_description = StringFormat("Volume is greater than the maximal allowed SYMBOL_VOLUME_MAX=%.2f", max_volume);
        return (false);
    }
    //--- get minimal step of volume changing
    double volume_step = m_symbol.LotsStep();
    int ratio = (int) MathRound(volume / volume_step);
    if (MathAbs(ratio * volume_step - volume) > 0.0000001) {
        error_description = StringFormat("Volume is not a multiple of the minimal step SYMBOL_VOLUME_STEP=%.2f, the closest correct volume is %.2f",
                volume_step, ratio * volume_step);
        return (false);
    }
    error_description = "Correct volume value";
    return (true);
}
//+------------------------------------------------------------------+
//| Check Freeze and Stops levels                                    |
//+------------------------------------------------------------------+
bool FreezeStopsLevels(double & level) {
    //--- check Freeze and Stops levels
    /*
       Type of order/position  |  Activation price  |  Check
       ------------------------|--------------------|--------------------------------------------
       Buy Limit order         |  Ask               |  Ask-OpenPrice  >= SYMBOL_TRADE_FREEZE_LEVEL
       Buy Stop order          |  Ask               |  OpenPrice-Ask  >= SYMBOL_TRADE_FREEZE_LEVEL
       Sell Limit order        |  Bid               |  OpenPrice-Bid  >= SYMBOL_TRADE_FREEZE_LEVEL
       Sell Stop order         |  Bid               |  Bid-OpenPrice  >= SYMBOL_TRADE_FREEZE_LEVEL
       Buy position            |  Bid               |  TakeProfit-Bid >= SYMBOL_TRADE_FREEZE_LEVEL
                               |                    |  Bid-StopLoss   >= SYMBOL_TRADE_FREEZE_LEVEL
       Sell position           |  Ask               |  Ask-TakeProfit >= SYMBOL_TRADE_FREEZE_LEVEL
                               |                    |  StopLoss-Ask   >= SYMBOL_TRADE_FREEZE_LEVEL
                              
       Buying is done at the Ask price                 |  Selling is done at the Bid price
       ------------------------------------------------|----------------------------------
       TakeProfit        >= Bid                        |  TakeProfit        <= Ask
       StopLoss          <= Bid                        |  StopLoss          >= Ask
       TakeProfit - Bid  >= SYMBOL_TRADE_STOPS_LEVEL   |  Ask - TakeProfit  >= SYMBOL_TRADE_STOPS_LEVEL
       Bid - StopLoss    >= SYMBOL_TRADE_STOPS_LEVEL   |  StopLoss - Ask    >= SYMBOL_TRADE_STOPS_LEVEL
    */
    if (!RefreshRates() || !m_symbol.Refresh())
        return (false);
    //--- FreezeLevel -> for pending order and modification
    double freeze_level = m_symbol.FreezeLevel() * m_symbol.Point();
    if (freeze_level == 0.0)
        freeze_level = (m_symbol.Ask() - m_symbol.Bid()) * 3.0;
    freeze_level *= 1.1;
    //--- StopsLevel -> for TakeProfit and StopLoss
    double stop_level = m_symbol.StopsLevel() * m_symbol.Point();
    if (stop_level == 0.0)
        stop_level = (m_symbol.Ask() - m_symbol.Bid()) * 3.0;
    stop_level *= 1.1;

    if (freeze_level <= 0.0 || stop_level <= 0.0)
        return (false);

    level = (freeze_level > stop_level) ? freeze_level : stop_level;
    //---
    return (true);
}
//+------------------------------------------------------------------+
//| Open position                                                    |
//+------------------------------------------------------------------+
void OpenPosition(const ENUM_POSITION_TYPE pos_type, const double level) {
    //--- buy
    if (pos_type == POSITION_TYPE_BUY) {
        double price = m_symbol.Ask();
        double sl = (InpStopLoss == 0) ? 0.0 : price - ExtStopLoss;
        if (sl != 0.0 && ExtStopLoss < level) // check sl
            sl = price - level;
        double tp = (InpTakeProfit == 0) ? 0.0 : price + ExtTakeProfit;
        if (tp != 0.0 && ExtTakeProfit < level) // check price
            tp = price + level;
        OpenBuy(sl, tp);
    }
    //--- sell
    if (pos_type == POSITION_TYPE_SELL) {
        double price = m_symbol.Bid();
        double sl = (InpStopLoss == 0) ? 0.0 : price + ExtStopLoss;
        if (sl != 0.0 && ExtStopLoss < level) // check sl
            sl = price + level;
        double tp = (InpTakeProfit == 0) ? 0.0 : price - ExtTakeProfit;
        if (tp != 0.0 && ExtTakeProfit < level) // check tp
            tp = price - level;
        OpenSell(sl, tp);
    }
}
//+------------------------------------------------------------------+
//| Open Buy position                                                |
//+------------------------------------------------------------------+
void OpenBuy(double sl, double tp) {
    sl = m_symbol.NormalizePrice(sl);
    tp = m_symbol.NormalizePrice(tp);

    double long_lot = 0.0;
    if (IntLotOrRisk == risk) {
        long_lot = m_money.CheckOpenLong(m_symbol.Ask(), sl);
        if (long_lot == 0.0) {
            m_waiting_transaction = false;
            return;
        }
    } else if (IntLotOrRisk == lot)
        long_lot = InpVolumeLorOrRisk;
    else {
        m_waiting_transaction = false;
        return;
    }
    if (m_symbol.LotsLimit() > 0.0) {
        int count_buys = 0;
        double volume_buys = 0.0;
        double volume_biggest_buys = 0.0;
        int count_sells = 0;
        double volume_sells = 0.0;
        double volume_biggest_sells = 0.0;
        CalculateAllPositions(count_buys, volume_buys, volume_biggest_buys,
            count_sells, volume_sells, volume_biggest_sells);
        if (volume_buys + volume_sells + long_lot > m_symbol.LotsLimit()) {
            Print("#0 Buy, Volume Buy (", DoubleToString(volume_buys, 2),
                ") + Volume Sell (", DoubleToString(volume_sells, 2),
                ") + Volume long (", DoubleToString(long_lot, 2),
                ") > Lots Limit (", DoubleToString(m_symbol.LotsLimit(), 2), ")");
            return;
        }
    }
    //--- check volume before OrderSend to avoid "not enough money" error (CTrade)
    double free_margin_check = m_account.FreeMarginCheck(m_symbol.Name(), ORDER_TYPE_BUY, long_lot, m_symbol.Ask());
    double margin_check = m_account.MarginCheck(m_symbol.Name(), ORDER_TYPE_SELL, long_lot, m_symbol.Bid());
    if (free_margin_check > margin_check) {
        if (m_trade.Buy(long_lot, m_symbol.Name(), m_symbol.Ask(), sl, tp)){ // CTrade::Buy -> "true"
            if (m_trade.ResultDeal() == 0) {
                if (m_trade.ResultRetcode() == 10009){ // trade order went to the exchange
                    m_waiting_transaction = true; // "true" -> it's forbidden to trade, we expect a transaction
                    m_waiting_order_ticket = m_trade.ResultOrder();
                } 
                else {
                    m_waiting_transaction = false;
                }
            } 
            else {
                if (m_trade.ResultRetcode() == 10009) {
                    m_waiting_transaction = true; // "true" -> it's forbidden to trade, we expect a transaction
                    m_waiting_order_ticket = m_trade.ResultOrder();
                } 
                else {
                    m_waiting_transaction = false;
                }
               
            }
        } else {
            m_waiting_transaction = false;
        }
    } 
    else {
        m_waiting_transaction = false;
        return;
    }
    //---
}
//+------------------------------------------------------------------+
//| Open Sell position                                               |
//+------------------------------------------------------------------+
void OpenSell(double sl, double tp) {
    sl = m_symbol.NormalizePrice(sl);
    tp = m_symbol.NormalizePrice(tp);

    double short_lot = 0.0;
    if (IntLotOrRisk == risk) {
        short_lot = m_money.CheckOpenShort(m_symbol.Bid(), sl);
        if (short_lot == 0.0) {
            m_waiting_transaction = false;            
            return;
        }
    } 
    else if (IntLotOrRisk == lot){
        short_lot = InpVolumeLorOrRisk;
    }
    else {
        m_waiting_transaction = false;
        return;
    }
    if (m_symbol.LotsLimit() > 0.0) {
        int count_buys = 0;
        double volume_buys = 0.0;
        double volume_biggest_buys = 0.0;
        int count_sells = 0;
        double volume_sells = 0.0;
        double volume_biggest_sells = 0.0;
        CalculateAllPositions(count_buys, volume_buys, volume_biggest_buys,
            count_sells, volume_sells, volume_biggest_sells);
        if (volume_buys + volume_sells + short_lot > m_symbol.LotsLimit())
            Print("#0 Buy, Volume Buy (", DoubleToString(volume_buys, 2),
                ") + Volume Sell (", DoubleToString(volume_sells, 2),
                ") + Volume short (", DoubleToString(short_lot, 2),
                ") > Lots Limit (", DoubleToString(m_symbol.LotsLimit(), 2), ")");
        return;
    }
    //--- check volume before OrderSend to avoid "not enough money" error (CTrade)
    double free_margin_check = m_account.FreeMarginCheck(m_symbol.Name(), ORDER_TYPE_SELL, short_lot, m_symbol.Bid());
    double margin_check = m_account.MarginCheck(m_symbol.Name(), ORDER_TYPE_SELL, short_lot, m_symbol.Bid());
    if (free_margin_check > margin_check) {
        if (m_trade.Sell(short_lot, m_symbol.Name(), m_symbol.Bid(), sl, tp)){ // CTrade::Sell -> "true"
            if (m_trade.ResultDeal() == 0) {
                if (m_trade.ResultRetcode() == 10009){ // trade order went to the exchange
                    m_waiting_transaction = true; // "true" -> it's forbidden to trade, we expect a transaction
                    m_waiting_order_ticket = m_trade.ResultOrder();
                } 
                else {
                    m_waiting_transaction = false;
                }
            } 
            else {
                if (m_trade.ResultRetcode() == 10009) {
                    m_waiting_transaction = true; // "true" -> it's forbidden to trade, we expect a transaction
                    m_waiting_order_ticket = m_trade.ResultOrder();
                } 
                else {
                    m_waiting_transaction = false;
                }
                
            }
        } else {
            m_waiting_transaction = false;
        }
    } else {
        m_waiting_transaction = false;
        return;
    }
    //---
}

//+------------------------------------------------------------------+
//| Trailing stop function                                           |
//+------------------------------------------------------------------+
void Trailing(const double stop_level) {
    /*
       Buying is done at the Ask price                 |  Selling is done at the Bid price
       ------------------------------------------------|----------------------------------
       TakeProfit        >= Bid                        |  TakeProfit        <= Ask
       StopLoss          <= Bid                        |  StopLoss          >= Ask
       TakeProfit - Bid  >= SYMBOL_TRADE_STOPS_LEVEL   |  Ask - TakeProfit  >= SYMBOL_TRADE_STOPS_LEVEL
       Bid - StopLoss    >= SYMBOL_TRADE_STOPS_LEVEL   |  StopLoss - Ask    >= SYMBOL_TRADE_STOPS_LEVEL
    */
    if (InpTrailingStop == 0)
        return;
    for (int i = PositionsTotal() - 1; i >= 0; i--) // returns the number of open positions
        if (m_position.SelectByIndex(i))
            if (m_position.Symbol() == m_symbol.Name() && m_position.Magic() == InpMagic) {
                if (m_position.PositionType() == POSITION_TYPE_BUY) {
                    if (m_position.PriceCurrent() - m_position.PriceOpen() > ExtTrailingStop + ExtTrailingStep){
                        if (m_position.StopLoss() < m_position.PriceCurrent() - (ExtTrailingStop + ExtTrailingStep)){
                            if (ExtTrailingStop >= stop_level) {
                                if (!m_trade.PositionModify(m_position.Ticket(),m_symbol.NormalizePrice(m_position.PriceCurrent() - ExtTrailingStop),m_position.TakeProfit()))
                                    Print("Modify ", m_position.Ticket(),
                                        " Position -> false. Result Retcode: ", m_trade.ResultRetcode(),
                                        ", description of result: ", m_trade.ResultRetcodeDescription());
                                RefreshRates();
                                m_position.SelectByIndex(i);
                                continue;
                    
                            }
                        }
                    }
                } 
                else {
                    if (m_position.PriceOpen() - m_position.PriceCurrent() > ExtTrailingStop + ExtTrailingStep)
                        if ((m_position.StopLoss() > (m_position.PriceCurrent() + (ExtTrailingStop + ExtTrailingStep))) ||(m_position.StopLoss() == 0)){
                            if (ExtTrailingStop >= stop_level) {
                                if (!m_trade.PositionModify(m_position.Ticket(), m_symbol.NormalizePrice(m_position.PriceCurrent() + ExtTrailingStop), m_position.TakeProfit())){
                                    Print("Modify ", m_position.Ticket(),
                                        " Position -> false. Result Retcode: ", m_trade.ResultRetcode(),
                                        ", description of result: ", m_trade.ResultRetcodeDescription());
                                RefreshRates();
                                m_position.SelectByIndex(i); 
                                
                            }
                        }
                    }
                }
            }
}
//+------------------------------------------------------------------+
//| Close positions                                                  |
//+------------------------------------------------------------------+
void ClosePositions(const ENUM_POSITION_TYPE pos_type) {
    for (int i = PositionsTotal() - 1; i >= 0; i--) // returns the number of current positions
        if (m_position.SelectByIndex(i)) // selects the position by index for further access to its properties
            if (m_position.Symbol() == m_symbol.Name() && m_position.Magic() == InpMagic)
                if (m_position.PositionType() == pos_type) // gets the position type
                    m_trade.PositionClose(m_position.Ticket()); // close a position by the specified symbol
}
//+------------------------------------------------------------------+
//| Close All positions                                                  |
//+------------------------------------------------------------------+
void CloseAllPositions() {
    for (int i = PositionsTotal() - 1; i >= 0; i--) // returns the number of current positions
        if (m_position.SelectByIndex(i)) // selects the position by index for further access to its properties
            if (m_position.Symbol() == m_symbol.Name() && m_position.Magic() == InpMagic)               
                    m_trade.PositionClose(m_position.Ticket()); // close a position by the specified symbol
}
//+------------------------------------------------------------------+
//| Calculate all positions                                          |
//+------------------------------------------------------------------+
void CalculateAllPositions(int & count_buys, double & volume_buys, double & volume_biggest_buys,
    int & count_sells, double & volume_sells, double & volume_biggest_sells) {
    count_buys = 0;
    volume_buys = 0.0;
    volume_biggest_buys = 0.0;
    count_sells = 0;
    volume_sells = 0.0;
    volume_biggest_sells = 0.0;
    for (int i = PositionsTotal() - 1; i >= 0; i--)
        if (m_position.SelectByIndex(i)) // selects the position by index for further access to its properties
            if (m_position.Symbol() == m_symbol.Name() && m_position.Magic() == InpMagic) {
                if (m_position.PositionType() == POSITION_TYPE_BUY) {
                    count_buys++;
                    volume_buys += m_position.Volume();
                    if (m_position.Volume() > volume_biggest_buys)
                        volume_biggest_buys = m_position.Volume();
                    continue;
                } 
                else if (m_position.PositionType() == POSITION_TYPE_SELL) {
                    count_sells++;
                    volume_sells += m_position.Volume();
                    if (m_position.Volume() > volume_biggest_sells)
                        volume_biggest_sells = m_position.Volume();
                }
            }
}
//+------------------------------------------------------------------+
//| Check time range function                                        |
//+------------------------------------------------------------------+
datetime starttime(){
    string currentdatestr=TimeToString(TimeCurrent(),TIME_DATE);
    string datetimenow=currentdatestr+ " "+InpTimeStart;
    return StringToTime(datetimenow);
}
datetime endtime(){
    string currentdatestr=TimeToString(TimeCurrent(),TIME_DATE);
    string datetimenow=currentdatestr+ " "+InpTimeStop;
    return StringToTime(datetimenow);
}
bool checktime(datetime start,datetime end) {
   datetime dt=TimeCurrent();                          // current time
   if(start<end) if(dt>=start && dt<end) return(true); // check if we are in the range
   if(start>=end) if(dt>=start|| dt<end) return(true);
   return(false);
}
//+------------------------------------------------------------------+
//| Trade function                                                   |
//+------------------------------------------------------------------+
void Trade() {
     //---
    if (m_waiting_transaction) {
        if (!m_transaction_confirmed) {
            Print("m_transaction_confirmed: ", m_transaction_confirmed);
            return;
        } else if (m_transaction_confirmed) {
            m_need_open_buy = false; // "true" -> need to open BUY
            m_need_open_sell = false; // "true" -> need to open SELL
            m_waiting_transaction = false; // "true" -> it's forbidden to trade, we expect a transaction
            m_waiting_order_ticket = 0; // ticket of the expected order
            m_transaction_confirmed = false; // "true" -> transaction confirmed
        }
    }
    if (m_need_open_buy) {
        double level;
        if (FreezeStopsLevels(level)) {
            m_waiting_transaction = true;
            OpenPosition(POSITION_TYPE_BUY, level);
        }
        //---
        return;
    }
    if (m_need_open_sell) {
        double level;
        if (FreezeStopsLevels(level)) {
            m_waiting_transaction = true;
            OpenPosition(POSITION_TYPE_SELL, level);
        }
        //---
        return;
    }
    //--- setup tradeing conditions
    SetupConditions();
//---    
}
//+------------------------------------------------------------------+
//| Setup conditions function                                        |
//+------------------------------------------------------------------+
void SetupConditions() {
   //--- we work only at the time of the birth of new bar
   static datetime PrevBars = 0;
   datetime time_0 = iTime(m_symbol.Name(), Period(), 0);
   if (time_0 == PrevBars)
      return;
   PrevBars = time_0;
   if (!RefreshRates()) {
      PrevBars = 0;
      return;
   }  
   double level;
   if (FreezeStopsLevels(level))
     Trailing(level);
   //---   
   InitZigZagHighLowArray(zigzag_array,zigzag_time);  
   if(InpZigZagDisplay){
      DrawZigZag();
   }
   ArraySetAsSeries(rsi_array,true);
   CopyBuffer(rsi_handler,0,0,3, rsi_array); 
   
   if(PositionsTotal() == 0) {          
      if(CheckSpread()){                          
         if(CheckZigZagForBuy()){
            if(CheckPriceForBuy()){
               if(CheckRSIForBuy()){
                  zigzag_a = zigzag_array[1];
                  zigzag_b = zigzag_array[0];
                  zigzag_time_a = zigzag_time[1];
                  zigzag_time_b = zigzag_time[0];
                   
                  if(InpZigZagDisplay){
                     DrawZigZagTrend();
                  }
                  if(InpFiboDisplay){
                     DrawFibo();
                  }
                  if(InpPositionOpenMode == follow){
                     m_need_open_sell = true;
                  }
                  if(InpPositionOpenMode == reverse){
                     m_need_open_buy = true;
                  } 
               }
            }     
         }            
         if(CheckZigZagForSell()){
            if(CheckPriceForSell()){
               if(CheckRSIForSell()){
                  zigzag_a = zigzag_array[1];
                  zigzag_b = zigzag_array[0];
                  zigzag_time_a = zigzag_time[1];
                  zigzag_time_b = zigzag_time[0];            
                  if(InpZigZagDisplay){
                     DrawZigZagTrend();
                  }
                  if(InpFiboDisplay){
                     DrawFibo();
                  }
                  if(InpPositionOpenMode == follow){
                     m_need_open_buy = true;
                  }
                  if(InpPositionOpenMode == reverse){
                     m_need_open_sell = true;
                  }
               }
            }            
         }
      }
      
   }
}
bool CheckZigZagForBuy(){
   if(zigzag_array[1] > zigzag_array[0]){
      if(CalculateRange(zigzag_array[1],zigzag_array[0]) >= InpZZPipsRangerMin){
         if(CalculateRange(zigzag_array[1],zigzag_array[0]) <= InpZZPipsRangerMax){
            if(CalculateRangePeriod(zigzag_time[1],zigzag_time[0]) >= InpZZPeriodRangerMin){
               if(CalculateRangePeriod(zigzag_time[1],zigzag_time[0]) <= InpZZPeriodRangerMax){
                  return true;     
               }
            }
         }      
      }   
   }
   return false;
}
bool CheckZigZagForSell(){
   if(zigzag_array[1] < zigzag_array[0]){
      if(CalculateRange(zigzag_array[1],zigzag_array[0]) >= InpZZPipsRangerMin){
         if(CalculateRange(zigzag_array[1],zigzag_array[0]) <= InpZZPipsRangerMax){
            if(CalculateRangePeriod(zigzag_time[1],zigzag_time[0]) >= InpZZPeriodRangerMin){
               if(CalculateRangePeriod(zigzag_time[1],zigzag_time[0]) <= InpZZPeriodRangerMax){
                  return true;                  
               }
            }
         }
      }
   }        
   return false;
}

bool CheckPriceForBuy(){   
   if(m_symbol.Ask() <= GetPriceAtFiboPercent(zigzag_a,zigzag_b,InpFiboOpenPositionLevel)){
      return true;
   }
   return false;
}

bool CheckPriceForSell(){   
   if(m_symbol.Bid() >= GetPriceAtFiboPercent(zigzag_a,zigzag_b,InpFiboOpenPositionLevel)){ 
      return true;
   }
   return false;
}

bool CheckRSIForBuy(){
   if(rsi_array[1] <= InpRSIValueCheckForBuy){ 
      return true;
   }  
   return false;
}

bool CheckRSIForSell(){
   if(rsi_array[1] >= InpRSIValueCheckForSell){  
      return true;
   }  
   return false;
}

int CalculateRangePeriod(datetime start, datetime stop){
   int range_period = 0;
   range_period = Bars(m_symbol.Name(),Period(),start,stop);
   return range_period;
}
double CalculateRange(double X, double Y){
   double range = 0.0; 
   range = MathAbs(X - Y);
  
   double rangeZigZag = -1;   
   if(m_symbol.Digits() == 3){
      rangeZigZag = range * 100;
   }   
   if(m_symbol.Digits() == 5){
      rangeZigZag = range * 10000;
   }
   return rangeZigZag;         
} 

double GetPriceAtFiboPercent(double price_at_x, double price_at_y, double percent_value_check){
    
   double price_at_percent = 0.0;
    
   double range_xy = MathAbs(price_at_x - price_at_y);
   
   if(price_at_x > price_at_y){
      if( percent_value_check == 0){
         price_at_percent =  price_at_y;
      }else if(percent_value_check == 100){
         price_at_percent = price_at_x;
      }else if(percent_value_check > 0 && percent_value_check < 100){       
         price_at_percent = price_at_y + (percent_value_check/100) * range_xy;      
      }else if(percent_value_check > 100){
         double x = percent_value_check - 100;
         price_at_percent = price_at_x + (x/100) * range_xy;
      }  
   }else if(price_at_x < price_at_y) {       
      if( percent_value_check == 0){
         price_at_percent =  price_at_y;
      }else if(percent_value_check == 100){
         price_at_percent = price_at_x;
      }else if(percent_value_check > 0 && percent_value_check < 100){       
          price_at_percent = price_at_y - (percent_value_check/100) * range_xy;  
      }else if(percent_value_check > 100){
         double x = percent_value_check - 100;
         price_at_percent = price_at_x - (x/100) * range_xy;
      }  
   }
   return price_at_percent;
}
bool CheckSpread(){
   double bid = SymbolInfoDouble(Symbol(),SYMBOL_BID);
   double ask = SymbolInfoDouble(Symbol(),SYMBOL_ASK);
   if(ask - bid <= InpSpreadLimit * _Point){
      return true;
   }
   return false;   
}

bool CheckBalanceStop(){
   if(InpBalancePercent > 0){
      if(m_account.Equity() >= ExtBalanceTP){
         Print("Stop Trading TP ", ExtBalanceTP);
         return true;
      }
      if(m_account.Equity() <= ExtBalanceSL){
         Print("Stop Trading SL ", ExtBalanceSL);
         return true;
      }
   }
   return false;
}

bool CheckTimeHourOpenPos(){
   MqlDateTime dt_struct;
   datetime dtSer=TimeCurrent(dt_struct);   
   for(int i = 0; i< ArraySize(hours_array); i++){
      if(dt_struct.hour == (int)hours_array[i]){
         return true;
         break;
      }
   
   } 
   return false;
}

bool CheckTimeMinuteOpenPos(){
   MqlDateTime dt_struct;
   datetime dtSer=TimeCurrent(dt_struct);
   if(dt_struct.min >= InpMinuteMin){
      if(dt_struct.min <= InpMinuteMax){
         return true;  
      }
   } 
   return false;
}

bool CheckDayOfWeek(){
   MqlDateTime dt_struct;
   datetime dtSer=TimeCurrent(dt_struct);
   if(InpDayOfWeek == all){
      return true;
   }else{
      if(dt_struct.day_of_week == InpDayOfWeek){
         return true;
      }   
   }
   return false;
}


void DrawZigZag(){  
   ObjectDelete(0,"Ma_AB");
   if (!ObjectCreate(0, "Ma_AB", OBJ_TREND, 0,zigzag_time[1], zigzag_array[1], zigzag_time[0], zigzag_array[0]))
      return;      
   ObjectSetInteger(0, "Ma_AB", OBJPROP_COLOR, InpZigZagColor);
   ObjectSetInteger(0, "Ma_AB", OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, "Ma_AB", OBJPROP_WIDTH, InpZigZagWidth);
   ObjectSetInteger(0, "Ma_AB", OBJPROP_BACK, false);
   ObjectSetInteger(0, "Ma_AB", OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0, "Ma_AB", OBJPROP_SELECTED, false);
   ObjectSetInteger(0, "Ma_AB", OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, "Ma_AB", OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, "Ma_AB", OBJPROP_ZORDER, 0);
}


void DrawZigZagTrend(){
   ObjectDelete(0,"Trend_AB");
   if (!ObjectCreate(0, "Trend_AB", OBJ_TREND, 0,zigzag_time_a, zigzag_a, zigzag_time_b, zigzag_b))
      return;      
   ObjectSetInteger(0, "Trend_AB", OBJPROP_COLOR, clrWhiteSmoke);
   ObjectSetInteger(0, "Trend_AB", OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, "Trend_AB", OBJPROP_WIDTH, 5);
   ObjectSetInteger(0, "Trend_AB", OBJPROP_BACK, false);
   ObjectSetInteger(0, "Trend_AB", OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0, "Trend_AB", OBJPROP_SELECTED, false);
   ObjectSetInteger(0, "Trend_AB", OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, "Trend_AB", OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, "Trend_AB", OBJPROP_ZORDER, 0);     
   
   ObjectDelete(0,"Trend_A");    
   if(!ObjectCreate(0,"Trend_A",OBJ_TEXT,0,zigzag_time_a,zigzag_a))
      return;
   ObjectSetString(0,"Trend_A",OBJPROP_TEXT,"A");
   ObjectSetString(0,"Trend_A",OBJPROP_FONT,"Arial");  
   ObjectSetInteger(0,"Trend_A",OBJPROP_FONTSIZE,10); 
   ObjectSetInteger(0,"Trend_A",OBJPROP_COLOR,clrWhiteSmoke);
   
    ObjectDelete(0,"Trend_B");
   if(!ObjectCreate(0,"Trend_B",OBJ_TEXT,0,zigzag_time_b,zigzag_b))
      return;
   ObjectSetString(0,"Trend_B",OBJPROP_TEXT,"B");
   ObjectSetString(0,"Trend_B",OBJPROP_FONT,"Arial");  
   ObjectSetInteger(0,"Trend_B",OBJPROP_FONTSIZE,10); 
   ObjectSetInteger(0,"Trend_B",OBJPROP_COLOR,clrWhiteSmoke); 
}

void DrawFibo(){
   ObjectDelete(0, "FIBO");
   if(!ObjectCreate(0, "FIBO", OBJ_FIBO, 0, zigzag_time_a, zigzag_a, zigzag_time_b, zigzag_b))
      return;
   ObjectSetInteger(0, "FIBO", OBJPROP_LEVELCOLOR, InpFiboColor);
   ObjectSetInteger(0, "FIBO", OBJPROP_LEVELSTYLE, STYLE_SOLID);
   ObjectSetInteger(0, "FIBO", OBJPROP_RAY_LEFT, true);
   ObjectSetInteger(0, "FIBO", OBJPROP_LEVELS, 2);
   ObjectSetDouble(0,  "FIBO", OBJPROP_LEVELVALUE, 0, 0.000);
   ObjectSetDouble(0,  "FIBO", OBJPROP_LEVELVALUE, 1, InpFiboOpenPositionLevel/100);   
   ObjectSetString(0,  "FIBO", OBJPROP_LEVELTEXT, 0, "0.0% (%$)");
   ObjectSetString(0,  "FIBO", OBJPROP_LEVELTEXT, 1, DoubleToString(InpFiboOpenPositionLevel,1) + ".0% (%$)");
}