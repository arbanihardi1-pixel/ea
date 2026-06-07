//+------------------------------------------------------------------+
//|                     Donchian Breakout EA                         |
//|                    Converted from TradingView                    |
//|                    Author: @millerrh (adapted)                   |
//|                                                                    |
//| Strategy:                                                         |
//|   Entry: Buy/Sell when Donchian Channel breaks out (M15)         |
//|   Exit: Trail a stop with the Donchian Channel bands             |
//|   Timeframe: M15                                                  |
//|   Assets: Forex (EURUSD, GBPUSD, etc) and Gold (XAUUSD)         |
//|   Position Sizing: Fixed Lot Size                                |
//|   Type: HYBRID - BUY/SELL with reversal logic                    |
//+------------------------------------------------------------------+

#property copyright "Adapted for MQL5"
#property version   "2.03"
#property strict

// Include Trade Library
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

// Global objects
CTrade trade;
CPositionInfo positionInfo;

// ==================== POSITION TYPE ENUM ====================

enum PositionType {
    NO_POSITION = 0,
    LONG_POSITION = 1,
    SHORT_POSITION = 2
};

PositionType currentPositionType = NO_POSITION;

// ==================== INPUT PARAMETERS ====================

// ========== ENTRY CONDITIONS MENU ==========
input group "═══ ENTRY CONDITIONS ═══";

input bool useCondition1_Breakout = true;        // ✓ Condition 1: Price breakout di atas dcUpper
input bool useCondition2_TrendCurrent = false;   // ✓ Condition 2: dcUpper > MA50 (trend up - current TF)
input bool useCondition3_TrendHTF = false;       // ✓ Condition 3: dcUpper > MA50 Daily (alignment - HTF)
input bool useCondition4_ADR = false;            // ✓ Condition 4: Channel width < 120% ADR (not extended)
input bool useCondition5_MASlope = false;        // ✓ Condition 5: MA slope naik (rising)

// ========== ENTRY EXECUTION MENU ==========
input group "═══ ENTRY EXECUTION ═══";

input string entryExecutionType = "Wick";        // Wick Mode: BuyStop/SellStop order / Close Mode: Market buy/sell
input double fixedLotSize = 0.1;                 // Fixed Lot Size

// ========== STOP LOSS MENU ==========
input group "═══ STOP LOSS MENU ═══";

input bool useStopLoss = true;                   // ☑ Enable/Disable Stop Loss
input bool useFixedStopLoss = true;              // ☑ Use Fixed Stop Loss (dcStop)
input bool useTrailingStop = true;               // ☑ Use Trailing Stop (dcLower/dcUpper)
input bool useCondition_Tight = true;            // ☑ Initial: dcStop (tight)
input bool useCondition_Wide = true;             // ☑ When Profit: Trail dengan dcLower (wide)

// ========== EXIT MENU ==========
input group "═══ EXIT CONDITION ═══";

input bool useExitOnReversal = true;             // ☑ Exit on Reversal Signal (breakout dcLower/dcUpper)
input bool useExitOnStopLoss = true;             // ☑ Exit on Stop Loss Hit

// ========== CANCEL LOGIC MENU ==========
input group "═══ CANCEL LOGIC ═══";

input bool useCancelLogic = true;                // ☑ Batalkan pending order jika MA stop rising

// ========== POSITION TYPE MENU ==========
input group "═══ POSITION TYPE ═══";

input bool allowBuySignal = true;                // ☑ Allow BUY Positions (breakout dcUpper)
input bool allowSellSignal = true;               // ☑ Allow SELL Positions (breakout dcLower)
input bool useHybridLogic = true;                // ☑ Use Hybrid Logic (Close opposite position on reversal)

// ==================== DONCHIAN CHANNEL INPUTS ====================
input group "═══ DONCHIAN CHANNEL SETTINGS ═══";

input int dcPeriodHigh = 20;                     // Upper Band:    Period
input color upperColor = clrBlue;                // Upper Band Color
input int dcPeriodLow = 10;                      // Lower Band:    Period
input color lowerColor = clrBlue;                // Lower Band Color
input color fillColor = clrGray;                 // Fill Color
input bool useTightStop = false;                 // Use a Tighter Channel for Initial Stop?
input int dcPeriod2Low = 8;                      // Initial Stop:    Period
input color tightColor = clrOrange;              // Initial Stop Color
input string trigInput = "Wick";                 // Execute Trades On... ('Wick' or 'Close')

// ==================== MOVING AVERAGE FILTERING INPUTS ====================
input group "═══ MOVING AVERAGE FILTERS ═══";

input bool useMaFilterSlope = false;             // Use Rising/Falling Moving Average as Filter?
input string tfSetSlope = "D1";                  // Timeframe of Moving Average (Slope)
input string maSlopeType = "SMA";                // MA Type For Filtering (Slope) - 'SMA' or 'EMA'
input int maSlopeLength = 5;                     // Moving Average: Length (Slope)

input bool useMaFilter = false;                  // Use Moving Average for Filtering (Current TF)?
input string maType = "SMA";                     // MA Type For Filtering - 'SMA' or 'EMA'
input int maLength = 50;                         // Moving Average: Length (Current TF)

input bool useMaFilter2 = false;                 // Use Moving Average for Filtering (HTF)?
input string tfSet = "D1";                       // Timeframe of Moving Average (HTF)
input string ma2Type = "SMA";                    // MA Type For Filtering (HTF) - 'SMA' or 'EMA'
input int ma2Length = 50;                        // Moving Average: Length (HTF)

// ==================== ADR FILTERING INPUTS ====================
input group "═══ ADR FILTERING ═══";

input bool useAdrFilter = false;                 // Use ADR for Filtering?
input int adrPerc = 120;                         // % of ADR Value

// ==================== POSITION MANAGEMENT ====================
input group "═══ POSITION MANAGEMENT ═══";

input int slippage = 10;                         // Slippage (pips)
input int magicNumber = 20240101;                // Magic Number

// ==================== GLOBAL VARIABLES ====================

int handleMaSlope = INVALID_HANDLE;
int handleMaFilter = INVALID_HANDLE;
int handleMaFilter2 = INVALID_HANDLE;

double dcUpper = 0;
double dcLower = 0;
double dcStop = 0;
double dcMid = 0;
double adrValue = 0;
double adrCompare = 0;
double srDistance = 0;

bool maRising = false;
bool maRisingPrev = false;
bool buySignal = false;
bool sellSignal = false;

// State tracking for trailing stop
double stopLevelLong = 0;
double stopLevelShort = 0;

// DEBUG: Show conditions status
bool condition1_Met = false;
bool condition2_Met = false;
bool condition3_Met = false;
bool condition4_Met = false;
bool condition5_Met = false;

// ==================== UTILITY FUNCTIONS ====================

// Convert timeframe string to ENUM_TIMEFRAMES
ENUM_TIMEFRAMES StringToTF(string tf)
{
    if(tf == "M1")   return PERIOD_M1;
    if(tf == "M5")   return PERIOD_M5;
    if(tf == "M15")  return PERIOD_M15;
    if(tf == "M30")  return PERIOD_M30;
    if(tf == "H1")   return PERIOD_H1;
    if(tf == "H4")   return PERIOD_H4;
    if(tf == "D1")   return PERIOD_D1;
    if(tf == "W1")   return PERIOD_W1;
    if(tf == "MN1")  return PERIOD_MN1;
    return PERIOD_CURRENT;
}

// Get MA method from string
ENUM_MA_METHOD GetMaMethod(string method)
{
    if(method == "EMA") return MODE_EMA;
    return MODE_SMA;
}

// Get MA value from indicator handle
double GetMAValue(int handle, int shift)
{
    double maBuffer[];
    ArraySetAsSeries(maBuffer, true);
    
    if(CopyBuffer(handle, 0, shift, 1, maBuffer) > 0)
    {
        return maBuffer[0];
    }
    return 0;
}

// Case-insensitive string comparison using built-in function
bool StringCompareCI(string str1, string str2)
{
    return StringCompare(StringUpper(str1), StringUpper(str2)) == 0;
}

// ==================== ONINIT FUNCTION ====================

int OnInit()
{
    // Set trade properties
    trade.SetExpertMagicNumber(magicNumber);
    trade.SetDeviationInPoints(slippage);
    
    // Request indicators on initialization
    if(!RequestIndicators())
    {
        Alert("Failed to request indicators");
        return INIT_FAILED;
    }
    
    Print("");
    Print("╔════════════════════════════════════════════╗");
    Print("║   Donchian Breakout EA - v2.03 (HYBRID)    ║");
    Print("║   Initialized on ", _Symbol, " M15        ║");
    Print("╚════════════════════════════════════════════╝");
    Print("");
    Print("ENTRY CONDITIONS:");
    Print("  1. Breakout: ", useCondition1_Breakout ? "✓ ENABLED" : "✗ DISABLED");
    Print("  2. Trend Current TF: ", useCondition2_TrendCurrent ? "✓ ENABLED" : "✗ DISABLED");
    Print("  3. Trend HTF: ", useCondition3_TrendHTF ? "✓ ENABLED" : "✗ DISABLED");
    Print("  4. ADR Filter: ", useCondition4_ADR ? "✓ ENABLED" : "✗ DISABLED");
    Print("  5. MA Slope: ", useCondition5_MASlope ? "✓ ENABLED" : "✗ DISABLED");
    Print("");
    Print("ENTRY EXECUTION: ", entryExecutionType);
    Print("POSITION TYPE:");
    Print("  BUY (dcUpper): ", allowBuySignal ? "✓ ALLOWED" : "✗ DISABLED");
    Print("  SELL (dcLower): ", allowSellSignal ? "✓ ALLOWED" : "✗ DISABLED");
    Print("  Hybrid Logic: ", useHybridLogic ? "✓ ENABLED" : "✗ DISABLED");
    Print("");
    Print("STOP LOSS CONFIGURATION:");
    Print("  Stop Loss: ", useStopLoss ? "✓ ENABLED" : "✗ DISABLED");
    Print("    ├─ Fixed SL: ", useFixedStopLoss ? "✓ ON" : "✗ OFF");
    Print("    ├─ Trailing SL: ", useTrailingStop ? "✓ ON" : "✗ OFF");
    Print("    └─ Trailing to Wide: ", useCondition_Wide ? "✓ ON" : "✗ OFF");
    Print("");
    Print("EXIT CONFIGURATION:");
    Print("  Exit on Reversal: ", useExitOnReversal ? "✓ ENABLED" : "✗ DISABLED");
    Print("  Exit on Stop Loss: ", useExitOnStopLoss ? "✓ ENABLED" : "✗ DISABLED");
    Print("");
    Print("CANCEL LOGIC: ", useCancelLogic ? "✓ ENABLED" : "✗ DISABLED");
    Print("");
    
    return INIT_SUCCEEDED;
}

// ==================== ONDEINIT FUNCTION ====================

void OnDeinit(const int reason)
{
    // Release indicator handles
    if(handleMaSlope != INVALID_HANDLE) IndicatorRelease(handleMaSlope);
    if(handleMaFilter != INVALID_HANDLE) IndicatorRelease(handleMaFilter);
    if(handleMaFilter2 != INVALID_HANDLE) IndicatorRelease(handleMaFilter2);
    
    Print("Expert Advisor deinitialized");
}

// ==================== INDICATOR REQUEST ====================

bool RequestIndicators()
{
    if(useMaFilterSlope || useCondition5_MASlope)
    {
        handleMaSlope = iMA(_Symbol, StringToTF(tfSetSlope), maSlopeLength, 0, GetMaMethod(maSlopeType), PRICE_CLOSE);
        if(handleMaSlope == INVALID_HANDLE)
        {
            Alert("Failed to create MA Slope indicator");
            return false;
        }
    }
    
    if(useMaFilter || useCondition2_TrendCurrent)
    {
        handleMaFilter = iMA(_Symbol, _Period, maLength, 0, GetMaMethod(maType), PRICE_CLOSE);
        if(handleMaFilter == INVALID_HANDLE)
        {
            Alert("Failed to create MA Filter indicator");
            return false;
        }
    }
    
    if(useMaFilter2 || useCondition3_TrendHTF)
    {
        handleMaFilter2 = iMA(_Symbol, StringToTF(tfSet), ma2Length, 0, GetMaMethod(ma2Type), PRICE_CLOSE);
        if(handleMaFilter2 == INVALID_HANDLE)
        {
            Alert("Failed to create MA Filter 2 indicator");
            return false;
        }
    }
    
    return true;
}

// ==================== UPDATE INDICATORS ====================

void UpdateIndicators()
{
    CalculateDonchian();
    
    if(useMaFilterSlope || useCondition5_MASlope)
    {
        double maSlopeValue = GetMAValue(handleMaSlope, 0);
        double maSlopePrev = GetMAValue(handleMaSlope, 1);
        maRising = maSlopeValue > maSlopePrev;
    }
    
    if(useAdrFilter || useCondition4_ADR)
    {
        CalculateADR();
    }
}

// ==================== DONCHIAN CHANNEL CALCULATION ====================

void CalculateDonchian()
{
    int indexHigh = iHighest(_Symbol, _Period, MODE_HIGH, dcPeriodHigh, 0);
    dcUpper = iHigh(_Symbol, _Period, indexHigh);
    
    int indexLow = iLowest(_Symbol, _Period, MODE_LOW, dcPeriodLow, 0);
    dcLower = iLow(_Symbol, _Period, indexLow);
    
    if(useTightStop)
    {
        int indexStop = iLowest(_Symbol, _Period, MODE_LOW, dcPeriod2Low, 0);
        dcStop = iLow(_Symbol, _Period, indexStop);
    }
    else
    {
        dcStop = dcLower;
    }
    
    dcMid = (dcUpper + dcLower) / 2.0;
}

// ==================== ADR CALCULATION ====================

void CalculateADR()
{
    double atr = iATR(_Symbol, PERIOD_D1, 21);
    double closePrice = iClose(_Symbol, PERIOD_D1, 0);
    
    if(closePrice == 0) return;
    
    adrValue = (atr / closePrice) * 100.0;
    adrCompare = (adrPerc * adrValue) / 100.0;
    
    if(dcUpper == 0) return;
    srDistance = ((dcUpper - dcLower) / dcUpper) * 100.0;
}

// ==================== SIGNAL CALCULATION ====================

void CalculateSignals()
{
    double currentHigh = iHigh(_Symbol, _Period, 0);
    double currentLow = iLow(_Symbol, _Period, 0);
    double currentClose = iClose(_Symbol, _Period, 0);
    
    double dcUpperPrev = iHigh(_Symbol, _Period, iHighest(_Symbol, _Period, MODE_HIGH, dcPeriodHigh, 1));
    double dcLowerPrev = iLow(_Symbol, _Period, iLowest(_Symbol, _Period, MODE_LOW, dcPeriodLow, 1));
    
    // === BUY SIGNAL ===
    if(trigInput == "Close")
    {
        buySignal = (currentClose >= dcUpperPrev);
    }
    else
    {
        buySignal = (currentHigh >= dcUpper);
    }
    
    // === SELL SIGNAL ===
    if(trigInput == "Close")
    {
        sellSignal = (currentClose <= dcLowerPrev);
    }
    else
    {
        sellSignal = (currentLow <= dcLower);
    }
}

// ==================== CHECK ENTRY CONDITIONS ====================

bool CheckEntryConditions()
{
    condition1_Met = true;
    condition2_Met = true;
    condition3_Met = true;
    condition4_Met = true;
    condition5_Met = true;
    
    // Condition 1
    if(useCondition1_Breakout)
    {
        condition1_Met = (buySignal || sellSignal);
    }
    
    // Condition 2
    double maFilterValue = useMaFilter || useCondition2_TrendCurrent ? GetMAValue(handleMaFilter, 0) : dcUpper;
    if(useCondition2_TrendCurrent)
    {
        condition2_Met = (dcUpper > maFilterValue);
    }
    
    // Condition 3
    double maFilter2Value = useMaFilter2 || useCondition3_TrendHTF ? GetMAValue(handleMaFilter2, 0) : dcUpper;
    if(useCondition3_TrendHTF)
    {
        condition3_Met = (dcUpper > maFilter2Value);
    }
    
    // Condition 4
    if(useCondition4_ADR)
    {
        condition4_Met = (srDistance < adrCompare);
    }
    
    // Condition 5
    if(useCondition5_MASlope)
    {
        condition5_Met = maRising;
    }
    
    static int debugCounter = 0;
    debugCounter++;
    if(debugCounter >= 10)
    {
        debugCounter = 0;
        Print("─────────────────────────────────────");
        Print("CONDITIONS STATUS:");
        Print("  1 (Breakout): ", condition1_Met ? "✓" : "✗");
        Print("  2 (Trend CTF): ", condition2_Met ? "✓" : "✗");
        Print("  3 (Trend HTF): ", condition3_Met ? "✓" : "✗");
        Print("  4 (ADR): ", condition4_Met ? "✓" : "✗");
        Print("  5 (MA Slope): ", condition5_Met ? "✓" : "✗");
        Print("─────────────────────────────────────");
    }
    
    return condition1_Met && condition2_Met && condition3_Met && condition4_Met && condition5_Met;
}

// ==================== GET CURRENT POSITION TYPE ====================

PositionType GetCurrentPositionType()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong posTicket = PositionGetTicket(i);
        if(posTicket == 0) continue;
        
        if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if(PositionGetInteger(POSITION_MAGIC) != magicNumber) continue;
        
        ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        
        if(type == POSITION_TYPE_BUY)
            return LONG_POSITION;
        else if(type == POSITION_TYPE_SELL)
            return SHORT_POSITION;
    }
    
    return NO_POSITION;
}

// ==================== EXECUTE BUY ENTRY ====================

void ExecuteBuyEntry()
{
    double volume = fixedLotSize;
    double stopPrice = useStopLoss ? dcStop : 0;
    
    if(StringCompareCI(entryExecutionType, "WICK"))
    {
        double entryPrice = dcUpper;
        trade.BuyStop(volume, entryPrice, _Symbol, stopPrice, 0);
        
        Print("");
        Print("╔════════════════════════════════════════╗");
        Print("║      ENTRY: BUY STOP (Wick Mode)       ║");
        Print("╠════════════════════════════════════════╣");
        Print("║ Entry:      ", entryPrice);
        Print("║ Stop Loss:  ", (useStopLoss ? (string)stopPrice : "NONE"));
        if(useStopLoss)
            Print("║ Risk:       ", MathAbs(entryPrice - stopPrice) * 10000, " pips");
        Print("╚════════════════════════════════════════╝");
        Print("");
    }
    else if(StringCompareCI(entryExecutionType, "CLOSE"))
    {
        trade.Buy(volume, _Symbol, 0, stopPrice, 0);
        
        Print("");
        Print("╔════════════════════════════════════════╗");
        Print("║      ENTRY: BUY MARKET (Close Mode)    ║");
        Print("╠════════════════════════════════════════╣");
        Print("║ Entry:      ", iClose(_Symbol, _Period, 0));
        Print("║ Stop Loss:  ", (useStopLoss ? (string)stopPrice : "NONE"));
        Print("╚════════════════════════════════════════╝");
        Print("");
    }
}

// ==================== EXECUTE SELL ENTRY ====================

void ExecuteSellEntry()
{
    double volume = fixedLotSize;
    double stopPrice = useStopLoss ? dcUpper : 0;
    
    if(StringCompareCI(entryExecutionType, "WICK"))
    {
        double entryPrice = dcLower;
        trade.SellStop(volume, entryPrice, _Symbol, stopPrice, 0);
        
        Print("");
        Print("╔════════════════════════════════════════╗");
        Print("║      ENTRY: SELL STOP (Wick Mode)      ║");
        Print("╠════════════════════════════════════════╣");
        Print("║ Entry:      ", entryPrice);
        Print("║ Stop Loss:  ", (useStopLoss ? (string)stopPrice : "NONE"));
        if(useStopLoss)
            Print("║ Risk:       ", MathAbs(entryPrice - stopPrice) * 10000, " pips");
        Print("╚════════════════════════════════════════╝");
        Print("");
    }
    else if(StringCompareCI(entryExecutionType, "CLOSE"))
    {
        trade.Sell(volume, _Symbol, 0, stopPrice, 0);
        
        Print("");
        Print("╔════════════════════════════════════════╗");
        Print("║      ENTRY: SELL MARKET (Close Mode)   ║");
        Print("╠════════════════════════════════════════╣");
        Print("║ Entry:      ", iClose(_Symbol, _Period, 0));
        Print("║ Stop Loss:  ", (useStopLoss ? (string)stopPrice : "NONE"));
        Print("╚════════════════════════════════════════╝");
        Print("");
    }
}

// ==================== MANAGE LONG POSITION ====================

void ManageLongPosition()
{
    if(!positionInfo.SelectByMagic(_Symbol, magicNumber))
        return;
    
    if(positionInfo.PositionType() != POSITION_TYPE_BUY)
        return;
    
    double posOpenPrice = positionInfo.PriceOpen();
    double currentStop = positionInfo.StopLoss();
    double trigSupport = (trigInput == "Close") ? iClose(_Symbol, _Period, 0) : iLow(_Symbol, _Period, 0);
    
    // === STOP LOSS MANAGEMENT ===
    if(useStopLoss && useTrailingStop)
    {
        bool inProfit = posOpenPrice <= dcStop;
        
        if(!inProfit && useFixedStopLoss && useCondition_Tight)
        {
            if(dcStop > currentStop)
            {
                trade.PositionModify(positionInfo.Ticket(), dcStop, 0);
                Print("📈 BUY SL Updated: ", currentStop, " → ", dcStop);
            }
        }
        else if(inProfit && useCondition_Wide)
        {
            if(dcLower > currentStop)
            {
                trade.PositionModify(positionInfo.Ticket(), dcLower, 0);
                Print("📈 BUY SL Trailed: ", currentStop, " → ", dcLower);
            }
        }
    }
    
    // === EXIT LOGIC ===
    
    // Exit on Reversal
    if(useExitOnReversal && sellSignal)
    {
        trade.PositionClose(positionInfo.Ticket());
        Print("📉 BUY Closed: Reversal Signal (dcLower breakout)");
        
        Print("");
        Print("╔════════════════════════════════════════╗");
        Print("║      EXIT: REVERSAL SIGNAL             ║");
        Print("╠════════════════════════════════════════╣");
        Print("║ Exit Price:  ", trigSupport);
        Print("║ Reason:      dcLower breakout");
        Print("╚════════════════════════════════════════╝");
        Print("");
    }
    
    // Exit on Stop Loss
    if(useExitOnStopLoss && useStopLoss && currentStop > 0)
    {
        if(trigSupport <= currentStop)
        {
            trade.PositionClose(positionInfo.Ticket());
            Print("❌ BUY Closed: Stop Loss Hit");
            
            Print("");
            Print("╔════════════════════════════════════════╗");
            Print("║      EXIT: STOP LOSS                   ║");
            Print("╠════════════════════════════════════════╣");
            Print("║ Exit Price:  ", trigSupport);
            Print("║ Stop Level:  ", currentStop);
            Print("╚════════════════════════════════════════╝");
            Print("");
        }
    }
}

// ==================== MANAGE SHORT POSITION ====================

void ManageShortPosition()
{
    if(!positionInfo.SelectByMagic(_Symbol, magicNumber))
        return;
    
    if(positionInfo.PositionType() != POSITION_TYPE_SELL)
        return;
    
    double posOpenPrice = positionInfo.PriceOpen();
    double currentStop = positionInfo.StopLoss();
    double trigResistance = (trigInput == "Close") ? iClose(_Symbol, _Period, 0) : iHigh(_Symbol, _Period, 0);
    
    // === STOP LOSS MANAGEMENT ===
    if(useStopLoss && useTrailingStop)
    {
        bool inProfit = posOpenPrice >= dcUpper;
        
        if(!inProfit && useFixedStopLoss && useCondition_Tight)
        {
            if(dcUpper < currentStop)
            {
                trade.PositionModify(positionInfo.Ticket(), dcUpper, 0);
                Print("📉 SELL SL Updated: ", currentStop, " → ", dcUpper);
            }
        }
        else if(inProfit && useCondition_Wide)
        {
            if(dcLower < currentStop)
            {
                trade.PositionModify(positionInfo.Ticket(), dcLower, 0);
                Print("📉 SELL SL Trailed: ", currentStop, " → ", dcLower);
            }
        }
    }
    
    // === EXIT LOGIC ===
    
    // Exit on Reversal
    if(useExitOnReversal && buySignal)
    {
        trade.PositionClose(positionInfo.Ticket());
        Print("📈 SELL Closed: Reversal Signal (dcUpper breakout)");
        
        Print("");
        Print("╔════════════════════════════════════════╗");
        Print("║      EXIT: REVERSAL SIGNAL             ║");
        Print("╠════════════════════════════════════════╣");
        Print("║ Exit Price:  ", trigResistance);
        Print("║ Reason:      dcUpper breakout");
        Print("╚════════════════════════════════════════╝");
        Print("");
    }
    
    // Exit on Stop Loss
    if(useExitOnStopLoss && useStopLoss && currentStop > 0)
    {
        if(trigResistance >= currentStop)
        {
            trade.PositionClose(positionInfo.Ticket());
            Print("❌ SELL Closed: Stop Loss Hit");
            
            Print("");
            Print("╔════════════════════════════════════════╗");
            Print("║      EXIT: STOP LOSS                   ║");
            Print("╠════════════════════════════════════════╣");
            Print("║ Exit Price:  ", trigResistance);
            Print("║ Stop Level:  ", currentStop);
            Print("╚════════════════════════════════════════╝");
            Print("");
        }
    }
}

// ==================== CLOSE ALL POSITIONS ====================

void CloseAllPositions(string positionType = "ALL", string reason = "")
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong posTicket = PositionGetTicket(i);
        if(posTicket == 0) continue;
        
        if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if(PositionGetInteger(POSITION_MAGIC) != magicNumber) continue;
        
        ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        
        bool shouldClose = false;
        string typeStr = "";
        
        if(type == POSITION_TYPE_BUY && (positionType == "BUY" || positionType == "ALL"))
        {
            shouldClose = true;
            typeStr = "BUY";
        }
        else if(type == POSITION_TYPE_SELL && (positionType == "SELL" || positionType == "ALL"))
        {
            shouldClose = true;
            typeStr = "SELL";
        }
        
        if(shouldClose)
        {
            trade.PositionClose(posTicket);
            Print(typeStr, " Position closed - ", reason);
        }
    }
}

// ==================== CANCEL PENDING ORDERS ====================

void CancelAllPendingOrders()
{
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong orderTicket = OrderGetTicket(i);
        if(orderTicket == 0) continue;
        
        if(OrderGetInteger(ORDER_MAGIC) != magicNumber) continue;
        
        ENUM_ORDER_STATE orderState = (ENUM_ORDER_STATE)OrderGetInteger(ORDER_STATE);
        
        // Cancel if order is pending or placed
        if(orderState == ORDER_STATE_PLACED)
        {
            trade.OrderDelete(orderTicket);
        }
    }
}

// ==================== ONTICK FUNCTION ====================

void OnTick()
{
    // Store previous values
    maRisingPrev = maRising;
    
    // Update indicator values
    UpdateIndicators();
    
    // Calculate signal logic
    CalculateSignals();
    
    // Get current position type
    currentPositionType = GetCurrentPositionType();
    
    // === HYBRID LOGIC ===
    
    // Check Buy Signal
    if(buySignal && allowBuySignal && CheckEntryConditions())
    {
        if(useHybridLogic && currentPositionType == SHORT_POSITION)
        {
            // Close SELL first
            CloseAllPositions("SELL", "Closing SELL for BUY entry");
            Print("📉 SELL Closed - BUY Entry Signal");
        }
        
        if(currentPositionType != LONG_POSITION)
        {
            ExecuteBuyEntry();
            currentPositionType = LONG_POSITION;
            stopLevelLong = dcStop;
        }
    }
    
    // Check Sell Signal
    if(sellSignal && allowSellSignal && CheckEntryConditions())
    {
        if(useHybridLogic && currentPositionType == LONG_POSITION)
        {
            // Close BUY first
            CloseAllPositions("BUY", "Closing BUY for SELL entry");
            Print("📈 BUY Closed - SELL Entry Signal");
        }
        
        if(currentPositionType != SHORT_POSITION)
        {
            ExecuteSellEntry();
            currentPositionType = SHORT_POSITION;
            stopLevelShort = dcUpper;
        }
    }
    
    // Manage open position
    if(currentPositionType == LONG_POSITION)
    {
        ManageLongPosition();
    }
    else if(currentPositionType == SHORT_POSITION)
    {
        ManageShortPosition();
    }
    
    // Cancel logic
    if(useCancelLogic && useMaFilterSlope && !maRising && maRisingPrev)
    {
        CancelAllPendingOrders();
        Print("⚠️ MA no longer rising - Orders cancelled");
    }
}

//+------------------------------------------------------------------+
//| END OF EXPERT ADVISOR                                            |
//+------------------------------------------------------------------+
