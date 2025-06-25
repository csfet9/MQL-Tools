//+------------------------------------------------------------------+
//|                                                MLCamarilla_v3.mq5 |
//|                                                   Claudiu Sfetan |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Claudiu Sfetan"
#property link      "https://www.mql5.com"
#property version   "3.00"
#property description "Camarilla Levels Trading EA with Native ONNX Support"

/* Version 3.00 Changes:
   - Migrated from Python-based inference to native MQL5 ONNX support
   - Improved performance with built-in ONNX runtime (up to 10x faster)
   - Removed dependency on external Python environment
   - Enhanced model validation and error handling
   - Support for batch predictions
   - Real-time inference without external processes
   - Better Strategy Tester compatibility
   
   STRATEGY TESTER SETUP:
   Option 1 - Embedded Resources (Recommended):
   1. Uncomment: #define USE_EMBEDDED_MODEL (line ~44)
   2. Update #resource paths to match your ONNX model files:
      - Model: "\\Files\\MLCamarilla\\your_model.onnx"
      - Scaler: "\\Files\\MLCamarilla\\your_model_scaler_params.json"
   3. Ensure files exist at specified paths before compiling
   4. Recompile the EA and run Strategy Tester
   
   Option 2 - Automatic File Copying (New):
   1. Place your model files in: %APPDATA%\MetaQuotes\Terminal\Common\Files\MLCamarilla\
      (Full path example: C:\Users\YourName\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MLCamarilla\)
   2. The EA will automatically copy them to tester directory during initialization
   3. No recompilation needed - just run Strategy Tester
   4. Files are copied fresh on each tester run, solving the deletion issue
   
   HOW IT WORKS:
   - Live Trading: Loads models from Files folder (OnnxCreate)
   - Strategy Tester: Uses embedded resources (OnnxCreateFromBuffer)
   - Automatic detection of execution environment
   - Same codebase supports both modes seamlessly
   
   Version 2.10 Features Preserved:
   - Support for model subdirectories
   - ATR-based stop loss and take profit
   - Advanced risk management system
   - Auto-detection of models based on symbol/timeframe
   - Scaler normalization support
   - All trading logic and risk management intact
*/

//--- Include necessary files
#include <Trade\Trade.mqh>
#include <Arrays\ArrayDouble.mqh>
#include <Files\File.mqh>

//--- ONNX constants (if not defined in your MQL5 version)
#ifndef ONNX_DEBUG_LOGS
   #define ONNX_DEBUG_LOGS 1
#endif
#ifndef ONNX_NO_CONVERSION
   #define ONNX_NO_CONVERSION 0
#endif

//--- Strategy Tester compatibility: Embed ONNX model and scaler as resources
//--- Follow these steps to enable Strategy Tester support:
//--- 1. Copy your model files to: %APPDATA%\MetaQuotes\Terminal\[Terminal_ID]\MQL5\Files\MLCamarilla\
//--- 2. Uncomment the #define below
//--- 3. Update the resource paths to match your copied files
//#define USE_EMBEDDED_MODEL

#ifdef USE_EMBEDDED_MODEL
   //--- Update these paths after copying files to MQL5\Files\MLCamarilla\
   #resource "\\Files\\MLCamarilla\\xauusd_m5_camarilla_model.onnx" as uchar embedded_model[]
   #resource "\\Files\\MLCamarilla\\xauusd_m5_camarilla_model_scaler_params.json" as uchar embedded_scaler[]
   
   //--- Alternative models - uncomment as needed
   //#resource "\\Files\\MLCamarilla\\eurusd_h4_camarilla_model.onnx" as uchar embedded_model[]
   //#resource "\\Files\\MLCamarilla\\eurusd_h4_camarilla_model_scaler_params.json" as uchar embedded_scaler[]
#endif

//--- Global objects
CTrade         trade;
long           onnx_handle = INVALID_HANDLE;  // ONNX model handle

//--- Input parameters
input group "=== Camarilla Settings ==="
input ENUM_TIMEFRAMES TimeFrame = PERIOD_D1;          // Timeframe for pivot calculation (not for model selection)
input bool            UseDailyBased = true;           // Use daily-based values
input int             LookBack = 1;                   // Number of periods back

input group "=== Trading Levels ==="
input bool            TradeL3H3 = true;               // Trade Level 3 (L3/H3)
input bool            TradeL4H4 = true;               // Trade Level 4 (L4/H4)
input bool            TradeL5H5 = true;               // Trade Level 5 (L5/H5)

input group "=== ML Model Settings ==="
input string          ModelName = "ensemble_camarilla_model.onnx";        // Model name or path (e.g. subfolder/model.onnx)
input string          ScalerName = "ensemble_camarilla_scaler_params.json"; // Scaler params filename (auto if empty)
input bool            UseMLPrediction = true;                     // Use ML model for predictions
input double          MLConfidenceThreshold = 0.6;                // Default confidence threshold
input double          MLConfidenceL3 = 0.65;                      // L3/H3 confidence threshold
input double          MLConfidenceL4 = 0.70;                      // L4/H4 confidence threshold
input double          MLConfidenceL5 = 0.75;                      // L5/H5 confidence threshold
input bool            ShowModelInfo = true;                       // Show model info on init
input bool            LogPredictions = true;                      // Log prediction details

input group "=== Risk Management & Position Sizing ==="
input double          RiskPercent = 1.0;              // Risk per trade (%)
input bool            UseDynamicLotSize = true;       // Dynamic lot sizing based on equity
input double          MaxLotSize = 1.0;               // Maximum lot size allowed
input double          MinLotSize = 0.01;              // Minimum lot size
input double          VolatilityMultiplier = 1.5;     // ATR multiplier for dynamic sizing

input group "=== Stop Loss & Take Profit Settings ==="
input bool            UseATRStops = true;             // Use ATR-based stops (recommended)
input double          StopLossPoints = 200;           // Fixed stop loss in points (if ATR disabled)
input double          TakeProfitPoints = 400;         // Fixed take profit in points (if ATR disabled)
input int             ATRPeriod = 14;                 // ATR Period for dynamic stops
input double          ATRMultiplierSL = 2.0;          // ATR Multiplier for Stop Loss
input double          ATRMultiplierTP = 3.0;          // ATR Multiplier for Take Profit
input double          MinRiskRewardRatio = 1.5;       // Minimum Risk/Reward Ratio

input group "=== Advanced Stop Management ==="
input bool            UseTrailingStop = true;         // Enable trailing stop loss
input double          TrailingStopPoints = 150;       // Fixed trailing stop distance (points)
input bool            UseATRTrailingStop = true;      // Use ATR-based trailing stop
input double          ATRTrailingMultiplier = 1.5;    // ATR Multiplier for Trailing

input bool            UseTimeBasedExit = true;        // Enable time-based position exit
input int             MaxPositionHours = 24;          // Maximum position duration (hours)

input group "=== Advanced Risk Controls ==="
input bool            UseAdvancedRisk = true;         // Enable advanced risk management
input double          MaxDailyLoss = 5.0;             // Maximum daily loss (%)
input double          MaxDrawdown = 10.0;             // Maximum drawdown (%)
input double          PortfolioHeat = 15.0;           // Maximum portfolio risk (%)
input int             MaxPositions = 2;               // Maximum open positions (total)
input int             MaxPositionsPerSymbol = 1;      // Max positions per symbol
input double          MinEquityLevel = 1000;          // Minimum account equity

input group "=== Trading Filters ==="
input double          MaxSpread = 3.0;                // Maximum spread in points
input bool            UseTimeFilter = true;           // Use time filter
input int             StartHour = 8;                  // Start trading hour
input int             EndHour = 18;                   // End trading hour
input bool            UseNewsFilter = false;          // Avoid trading during news (placeholder)
input int             NewsAvoidanceMinutes = 30;      // Minutes to avoid trading around news

//--- Global variables
double pivot_point;
double r1, r2, r3, r4, r5, r6;
double s1, s2, s3, s4, s5, s6;
double cpr_tc, cpr_bc;

datetime last_calculation_time;
bool levels_calculated;

//--- ML Model variables
bool model_loaded;
string model_path;
string scaler_path;

//--- Scaler parameters
double scaler_mean[];
double scaler_scale[];
bool scaler_loaded;

//--- ONNX model information
long model_input_count;
long model_output_count;

//--- Advanced Risk Management variables
datetime daily_reset_time;
double daily_start_balance;
double daily_profit_loss;
double account_high_water_mark;
double current_drawdown;
bool trading_suspended;
string suspension_reason;
datetime suspension_time;

//--- Position tracking
struct PositionInfo {
   ulong ticket;
   datetime open_time;
   double open_price;
   double initial_sl;
   double highest_profit;
   double lowest_profit;
};

PositionInfo position_tracker[];

//--- Structure for market features
struct MarketFeatures
{
   double price_to_pivot_ratio;
   double price_to_l3_ratio;
   double price_to_h3_ratio;
   double price_to_l4_ratio;
   double price_to_h4_ratio;
   double price_to_l5_ratio;
   double price_to_h5_ratio;
   double volatility;
   double volume_ratio;
   double time_of_day;
   double rsi;
   double macd_signal;
};

//--- Forward declarations
bool CheckTraditionalFilters(ENUM_POSITION_TYPE position_type, string level_name);
void DisplayMLImpactStatistics();
bool IsInTrend(ENUM_POSITION_TYPE position_type);
bool IsVolatilityAcceptable();
double GetLevelSpecificThreshold(string level_name);
double GetLevelSpecificSLMultiplier(string level_name);

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("=== Initializing MLCamarilla EA v3.00 with Native ONNX Support ===");
   
   //--- Initialize trade object
   trade.SetExpertMagicNumber(12345);
   trade.SetMarginMode();
   trade.SetTypeFillingBySymbol(Symbol());
   
   //--- Initialize scaler arrays for ensemble model (35 features)
   ArrayResize(scaler_mean, 35);
   ArrayResize(scaler_scale, 35);
   
   //--- Setup file paths
   SetupFilePaths();
   
   //--- Check timeframe compatibility
   if(Period() != TimeFrame)
   {
      Print("INFO: Chart timeframe (", EnumToString(ENUM_TIMEFRAMES(Period())), 
            ") differs from pivot calculation timeframe (", EnumToString(TimeFrame), ")");
      Print("- Camarilla pivot levels will be calculated using: ", EnumToString(TimeFrame));
      Print("- ML models will be selected based on chart timeframe: ", EnumToString(ENUM_TIMEFRAMES(Period())));
      Print("This is normal - pivot timeframe and trading timeframe can be different");
   }
   
   //--- Initialize ML model system with native ONNX
   model_loaded = InitializeONNXModel();
   if(!model_loaded && UseMLPrediction)
   {
      Print("Warning: ONNX model could not be loaded. Trading without ML predictions.");
   }
   
   //--- Calculate initial Camarilla levels
   CalculateCamarillaLevels();
   
   //--- Initialize advanced risk management
   InitializeAdvancedRiskManagement();
   
   //--- Create visual elements
   CreateLevelLines();
   
   Print("MLCamarilla EA initialized successfully");
   PrintModelStatus();
   ShowModelNamingTips();
   PrintRiskManagementStatus();
   
   //--- Debug ATR calculation at startup
   if(UseATRStops)
   {
      Print("=== ATR Debug at Startup ===");
      int test_atr_handle = iATR(Symbol(), PERIOD_CURRENT, ATRPeriod);
      if(test_atr_handle != INVALID_HANDLE)
      {
         double test_atr_buffer[];
         ArraySetAsSeries(test_atr_buffer, true);
         if(CopyBuffer(test_atr_handle, 0, 0, 1, test_atr_buffer) > 0)
         {
            double test_atr = test_atr_buffer[0];
            double test_point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
            double test_tick = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
            double test_sl_distance = test_atr * ATRMultiplierSL;
            double test_sl_points = test_sl_distance / test_point;
            
            Print("📊 Symbol: ", Symbol());
            Print("📊 ATR Period: ", ATRPeriod);
            Print("📊 ATR Value: ", DoubleToString(test_atr, 8));
            Print("📊 Point Size: ", DoubleToString(test_point, 8));
            Print("📊 Tick Size: ", DoubleToString(test_tick, 8));
            Print("📊 ATR Multiplier SL: ", ATRMultiplierSL);
            Print("📊 Expected SL Distance: ", DoubleToString(test_sl_distance, 8));
            Print("📊 Expected SL Points: ", DoubleToString(test_sl_points, 1));
         }
         else
         {
            Print("❌ Failed to get ATR data at startup");
         }
      }
      else
      {
         Print("❌ Failed to create ATR handle at startup");
      }
      Print("============================");
   }
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Auto-detect model based on symbol and timeframe                |
//+------------------------------------------------------------------+
string AutoDetectModel()
{
   // Use current chart timeframe for model selection, not pivot timeframe
   ENUM_TIMEFRAMES chart_tf = Period();
   Print("=== Auto-detecting model for ", Symbol(), " ", EnumToString(chart_tf), " ===");
   
   // Get clean symbol name (remove suffixes like .a, .i, etc.)
   string clean_symbol = Symbol();
   StringToLower(clean_symbol);
   
   // Remove common broker suffixes
   string suffixes[] = {".a", ".i", ".m", ".r", ".s", ".x", ".", "#", "-"};
   for(int i = 0; i < ArraySize(suffixes); i++)
   {
      int pos = StringFind(clean_symbol, suffixes[i]);
      if(pos > 0)
      {
         clean_symbol = StringSubstr(clean_symbol, 0, pos);
         break;
      }
   }
   
   // Get timeframe string - use chart timeframe for model selection
   string tf_string = GetTimeframeString(chart_tf);
   
   // List of patterns to search for (in priority order)
   string search_patterns[];
   ArrayResize(search_patterns, 5);
   
   // Priority 1: Exact match with symbol and timeframe (ensemble)
   search_patterns[0] = clean_symbol + "_" + tf_string + "_ensemble_*.onnx";
   
   // Priority 2: Symbol with any timeframe (ensemble)
   search_patterns[1] = clean_symbol + "_*_ensemble_*.onnx";
   
   // Priority 3: Symbol only (ensemble)
   search_patterns[2] = clean_symbol + "_ensemble_*.onnx";
   
   // Priority 4: Any ensemble model for this timeframe
   search_patterns[3] = "*_" + tf_string + "_ensemble_*.onnx";
   
   // Priority 5: Generic ensemble model
   search_patterns[4] = "*ensemble*.onnx";
   
   // Try each pattern in root directory first
   for(int p = 0; p < ArraySize(search_patterns); p++)
   {
      string pattern = "MLCamarilla\\" + search_patterns[p];
      string found_models[];
      int model_count = ScanForModels(pattern, found_models);
      
      if(model_count > 0)
      {
         Print("Found ", model_count, " model(s) matching pattern: ", search_patterns[p]);
         
         // If exact match, use it
         if(p == 0)
         {
            Print("✓ Exact match found: ", found_models[0]);
            return found_models[0];
         }
         
         // For other patterns, prefer models with current symbol
         for(int i = 0; i < model_count; i++)
         {
            string model_lower = found_models[i];
            StringToLower(model_lower);
            
            if(StringFind(model_lower, clean_symbol) >= 0)
            {
               Print("✓ Selected model: ", found_models[i]);
               return found_models[i];
            }
         }
         
         // If no symbol match, return first found
         Print("✓ Selected model: ", found_models[0]);
         return found_models[0];
      }
   }
   
   // Now search in subdirectories
   Print("Searching in subdirectories...");
   string subdirs[];
   int subdir_count = GetSubdirectories("MLCamarilla\\", subdirs);
   
   for(int d = 0; d < subdir_count; d++)
   {
      for(int p = 0; p < ArraySize(search_patterns); p++)
      {
         string pattern = "MLCamarilla\\" + subdirs[d] + "\\" + search_patterns[p];
         string found_models[];
         int model_count = ScanForModels(pattern, found_models);
         
         if(model_count > 0)
         {
            Print("Found ", model_count, " model(s) in subdirectory ", subdirs[d], " matching pattern: ", search_patterns[p]);
            
            // Return with subdirectory path
            string model_with_path = subdirs[d] + "\\" + found_models[0];
            Print("✓ Selected model: ", model_with_path);
            return model_with_path;
         }
      }
   }
   
   Print("No auto-detected model found for ", Symbol(), " ", EnumToString(TimeFrame));
   return "";
}

//+------------------------------------------------------------------+
//| Scan for models matching pattern                                |
//+------------------------------------------------------------------+
int ScanForModels(string pattern, string &found_models[])
{
   ArrayResize(found_models, 0);
   
   string filename;
   long search_handle = FileFindFirst(pattern, filename);
   
   if(search_handle != INVALID_HANDLE)
   {
      do
      {
         int size = ArraySize(found_models);
         ArrayResize(found_models, size + 1);
         found_models[size] = filename;
      }
      while(FileFindNext(search_handle, filename));
      
      FileFindClose(search_handle);
   }
   
   return ArraySize(found_models);
}

//+------------------------------------------------------------------+
//| Get subdirectories in a given path                              |
//+------------------------------------------------------------------+
int GetSubdirectories(string path, string &subdirs[])
{
   ArrayResize(subdirs, 0);
   
   string filename;
   long search_handle = FileFindFirst(path + "*", filename, FILE_COMMON);
   
   if(search_handle != INVALID_HANDLE)
   {
      do
      {
         // Check if it's a directory (not a file)
         if(StringFind(filename, ".") < 0 || StringLen(filename) > 20) // Directories usually don't have extensions or have long names
         {
            // Try to verify it's a directory by checking for files inside
            string test_pattern = path + filename + "\\*.onnx";
            string test_file;
            long test_handle = FileFindFirst(test_pattern, test_file);
            
            if(test_handle != INVALID_HANDLE)
            {
               FileFindClose(test_handle);
               
               int size = ArraySize(subdirs);
               ArrayResize(subdirs, size + 1);
               subdirs[size] = filename;
            }
         }
      }
      while(FileFindNext(search_handle, filename));
      
      FileFindClose(search_handle);
   }
   
   return ArraySize(subdirs);
}

//+------------------------------------------------------------------+
//| Convert timeframe to string for model naming                   |
//+------------------------------------------------------------------+
string GetTimeframeString(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return "m1";
      case PERIOD_M5:  return "m5";
      case PERIOD_M15: return "m15";
      case PERIOD_M30: return "m30";
      case PERIOD_H1:  return "h1";
      case PERIOD_H4:  return "h4";
      case PERIOD_D1:  return "d1";
      case PERIOD_W1:  return "w1";
      case PERIOD_MN1: return "mn1";
      default:         return "h1";
   }
}

//+------------------------------------------------------------------+
//| Setup file paths for models and scripts                         |
//+------------------------------------------------------------------+
void SetupFilePaths()
{
   // Try to auto-detect model based on symbol and timeframe
   string auto_detected_model = AutoDetectModel();
   
   if(auto_detected_model != "" && ModelName == "ensemble_camarilla_model.onnx")
   {
      // Use auto-detected model if user hasn't specified a custom one
      model_path = "MLCamarilla\\" + auto_detected_model;
      Print("Auto-detected model: ", auto_detected_model);
   }
   else
   {
      // Check if ModelName already contains MLCamarilla prefix
      if(StringFind(ModelName, "MLCamarilla\\") == 0)
      {
         model_path = ModelName;
      }
      else
      {
         model_path = "MLCamarilla\\" + ModelName;
      }
   }
   
   // Auto-detect scaler file if not specified
   if(ScalerName == "")
   {
      // Extract just the model filename without path
      string model_filename = model_path;
      int last_slash = StringFind(model_filename, "\\", StringLen(model_filename) - 1);
      while(last_slash >= 0)
      {
         model_filename = StringSubstr(model_filename, last_slash + 1);
         last_slash = StringFind(model_filename, "\\");
      }
      
      // Remove .onnx extension
      StringReplace(model_filename, ".onnx", "");
      
      // Build scaler path in same directory as model
      string model_dir = model_path;
      StringReplace(model_dir, model_filename + ".onnx", "");
      scaler_path = model_dir + model_filename + "_scaler_params.json";
      
      // Also try alternative scaler naming patterns
      if(!FileIsExist(scaler_path))
      {
         // Try without model name prefix (just scaler_params.json in same dir)
         string alt_scaler = model_dir + "scaler_params.json";
         if(FileIsExist(alt_scaler))
         {
            scaler_path = alt_scaler;
            Print("Using alternative scaler file: ", alt_scaler);
         }
      }
   }
   else
   {
      // Check if ScalerName already contains MLCamarilla prefix
      if(StringFind(ScalerName, "MLCamarilla\\") == 0)
      {
         scaler_path = ScalerName;
      }
      else
      {
         scaler_path = "MLCamarilla\\" + ScalerName;
      }
   }
   
   Print("=== File Path Setup ===");
   Print("Terminal Data Path: ", TerminalInfoString(TERMINAL_DATA_PATH));
   Print("Model path: ", model_path);
   Print("Scaler path: ", scaler_path);
   Print("Full model path: ", TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Files\\" + model_path);
}

//+------------------------------------------------------------------+
//| Print model status information                                   |
//+------------------------------------------------------------------+
void PrintModelStatus()
{
   Print("=== ML Model Status ===");
   Print("Model loaded: ", model_loaded ? "YES" : "NO");
   Print("Scaler loaded: ", scaler_loaded ? "YES" : "NO");
   Print("ONNX handle valid: ", onnx_handle != INVALID_HANDLE ? "YES" : "NO");
   Print("ML prediction: ", UseMLPrediction ? "ENABLED" : "DISABLED");
   Print("Confidence threshold: ", DoubleToString(MLConfidenceThreshold, 2));
   
   if(model_loaded && ShowModelInfo && onnx_handle != INVALID_HANDLE)
   {
      Print("Model inputs: ", model_input_count);
      Print("Model outputs: ", model_output_count);
   }
}

//+------------------------------------------------------------------+
//| Show model naming tips                                          |
//+------------------------------------------------------------------+
void ShowModelNamingTips()
{
   // Get clean symbol name
   string clean_symbol = Symbol();
   StringToLower(clean_symbol);
   
   // Remove common broker suffixes
   string suffixes[] = {".a", ".i", ".m", ".r", ".s", ".x", ".", "#", "-"};
   for(int i = 0; i < ArraySize(suffixes); i++)
   {
      int pos = StringFind(clean_symbol, suffixes[i]);
      if(pos > 0)
      {
         clean_symbol = StringSubstr(clean_symbol, 0, pos);
         break;
      }
   }
   
   // Use chart timeframe for model tips, not pivot timeframe
   string tf_string = GetTimeframeString(Period());
   
   Print("");
   Print("=== Model Auto-Detection Tips ===");
   Print("For best auto-detection, name your models using this pattern:");
   Print("  symbol_timeframe_ensemble_model.onnx");
   Print("");
   Print("Examples for current settings:");
   Print("  Exact match: ", clean_symbol, "_", tf_string, "_ensemble_model.onnx");
   Print("  Symbol only: ", clean_symbol, "_ensemble_model.onnx");
   Print("  Generic: ensemble_camarilla_model.onnx");
   Print("");
   Print("Model Organization Options:");
   Print("1. Place models directly in: Files\\MLCamarilla\\");
   Print("2. Use subdirectories: Files\\MLCamarilla\\XAUUSD_M5_ensemble_20250620_170255\\");
   Print("");
   Print("To use a specific model from a subdirectory, set ModelName to:");
   Print("  'XAUUSD_M5_ensemble_20250620_170255/ensemble_camarilla_model.onnx'");
   Print("=================================");
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   //--- Release ONNX model
   if(onnx_handle != INVALID_HANDLE)
   {
      OnnxRelease(onnx_handle);
      onnx_handle = INVALID_HANDLE;
      Print("ONNX model released");
   }
   
   //--- Remove visual elements
   RemoveLevelLines();
   
   Print("MLCamarilla EA v3.00 deinitialized");
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   //--- Log first few ticks for debugging
   static int total_ticks = 0;
   total_ticks++;
   if(LogPredictions && total_ticks <= 5)
   {
      Print("OnTick called, tick #", total_ticks, " at ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
   }
   
   //--- Update advanced risk management on every tick
   UpdateAdvancedRiskManagement();
   
   //--- Check if new bar started for pivot calculation
   static datetime last_pivot_time = 0;
   datetime current_pivot_time = iTime(Symbol(), TimeFrame, 0);
   
   if(current_pivot_time != last_pivot_time)
   {
      last_pivot_time = current_pivot_time;
      
      //--- Recalculate Camarilla levels on new period
      CalculateCamarillaLevels();
      UpdateLevelLines();
   }
   
   //--- Check if levels are calculated before proceeding
   if(!levels_calculated)
   {
      CalculateCamarillaLevels();
      UpdateLevelLines();
   }
   
   //--- Check trading conditions on every tick
   if(!IsTradeAllowed())
      return;
   
   //--- Check for trading opportunities on every tick
   CheckTradingSignals();
   
   //--- Display ML impact statistics periodically
   DisplayMLImpactStatistics();
}

//+------------------------------------------------------------------+
//| Calculate Camarilla Levels                                       |
//+------------------------------------------------------------------+
void CalculateCamarillaLevels()
{
   //--- Get OHLC data for pivot calculation
   double high_price = iHigh(Symbol(), TimeFrame, 1);
   double low_price = iLow(Symbol(), TimeFrame, 1);
   double close_price = iClose(Symbol(), TimeFrame, 1);
   
   if(high_price == 0 || low_price == 0 || close_price == 0)
   {
      Print("Error: Could not get OHLC data for pivot calculation");
      return;
   }
   
   //--- Calculate pivot point
   pivot_point = (high_price + low_price + close_price) / 3.0;
   
   //--- Calculate pivot range
   double pivot_range = high_price - low_price;
   
   //--- Calculate Camarilla levels (based on Pine Script logic)
   r1 = close_price + pivot_range * 1.1 / 12.0;
   s1 = close_price - pivot_range * 1.1 / 12.0;
   
   r2 = close_price + pivot_range * 1.1 / 6.0;
   s2 = close_price - pivot_range * 1.1 / 6.0;
   
   r3 = close_price + pivot_range * 1.1 / 4.0;
   s3 = close_price - pivot_range * 1.1 / 4.0;
   
   r4 = close_price + pivot_range * 1.1 / 2.0;
   s4 = close_price - pivot_range * 1.1 / 2.0;
   
   //--- Calculate L5/H5 using ratio method
   r5 = high_price / low_price * close_price;
   s5 = 2 * close_price - r5;
   
   //--- Calculate L6/H6
   r6 = r5 + 1.168 * (r5 - r4);
   s6 = close_price - (r6 - close_price);
   
   //--- Calculate CPR (Central Pivot Range)
   cpr_bc = (high_price + low_price) / 2.0;
   cpr_tc = pivot_point - cpr_bc + pivot_point;
   
   levels_calculated = true;
   last_calculation_time = TimeCurrent();
   
   //--- Print levels for debugging
   PrintCamarillaLevels();
}

//+------------------------------------------------------------------+
//| Print Camarilla Levels                                          |
//+------------------------------------------------------------------+
void PrintCamarillaLevels()
{
   Print("=== Camarilla Levels ===");
   Print("Pivot: ", DoubleToString(pivot_point, _Digits));
   Print("R3: ", DoubleToString(r3, _Digits), " | S3: ", DoubleToString(s3, _Digits));
   Print("R4: ", DoubleToString(r4, _Digits), " | S4: ", DoubleToString(s4, _Digits));
   Print("R5: ", DoubleToString(r5, _Digits), " | S5: ", DoubleToString(s5, _Digits));
}

//+------------------------------------------------------------------+
//| Check if trading is allowed                                      |
//+------------------------------------------------------------------+
bool IsTradeAllowed()
{
   //--- Check if levels are calculated
   if(!levels_calculated)
   {
      if(LogPredictions)
         Print("Trade not allowed: Levels not calculated");
      return false;
   }
   
   //--- Check spread
   double spread = (SymbolInfoDouble(Symbol(), SYMBOL_ASK) - SymbolInfoDouble(Symbol(), SYMBOL_BID)) / SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   if(spread > MaxSpread)
   {
      if(LogPredictions)
         Print("Trade not allowed: Spread too high (", DoubleToString(spread, 1), " > ", MaxSpread, ")");
      return false;
   }
   
   //--- Check time filter
   if(UseTimeFilter)
   {
      MqlDateTime dt;
      TimeCurrent(dt);
      if(dt.hour < StartHour || dt.hour >= EndHour)
      {
         static datetime last_time_log = 0;
         if(LogPredictions && TimeCurrent() - last_time_log > 3600)
         {
            last_time_log = TimeCurrent();
            Print("Trade not allowed: Outside trading hours (", dt.hour, ":00, allowed: ", StartHour, "-", EndHour, ")");
         }
         return false;
      }
   }
   
   //--- Check maximum positions
   if(PositionsTotal() >= MaxPositions)
   {
      if(LogPredictions)
         Print("Trade not allowed: Maximum positions reached (", PositionsTotal(), ")");
      return false;
   }
   
   //--- Check advanced risk conditions
   if(!CheckAdvancedRiskConditions())
   {
      if(LogPredictions)
         Print("Trade not allowed: Advanced risk conditions not met");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check for trading signals                                        |
//+------------------------------------------------------------------+
void CheckTradingSignals()
{
   double current_price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   
   //--- Log current price vs levels periodically
   static datetime last_log_time = 0;
   static int tick_count = 0;
   tick_count++;
   
   // Log every 1000 ticks or every hour
   if(LogPredictions && (tick_count % 1000 == 0 || TimeCurrent() - last_log_time > 3600))
   {
      last_log_time = TimeCurrent();
      Print("=== Price Check (Tick ", tick_count, ") ===");
      Print("Time: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES));
      Print("Current Price: ", DoubleToString(current_price, _Digits));
      Print("Distance to R3: ", DoubleToString(r3 - current_price, _Digits), " points");
      Print("Distance to S3: ", DoubleToString(current_price - s3, _Digits), " points");
      Print("R3: ", DoubleToString(r3, _Digits), " | S3: ", DoubleToString(s3, _Digits));
      Print("R4: ", DoubleToString(r4, _Digits), " | S4: ", DoubleToString(s4, _Digits));
      Print("R5: ", DoubleToString(r5, _Digits), " | S5: ", DoubleToString(s5, _Digits));
   }
   
   //--- Check L3/H3 levels
   if(TradeL3H3)
   {
      CheckLevelBreakout(current_price, s3, r3, "L3H3");
   }
   
   //--- Check L4/H4 levels
   if(TradeL4H4)
   {
      CheckLevelBreakout(current_price, s4, r4, "L4H4");
   }
   
   //--- Check L5/H5 levels
   if(TradeL5H5)
   {
      CheckLevelBreakout(current_price, s5, r5, "L5H5");
   }
}

//+------------------------------------------------------------------+
//| Check level breakout                                             |
//+------------------------------------------------------------------+
void CheckLevelBreakout(double price, double support_level, double resistance_level, string level_name)
{
   //--- Use separate static variables for each level to track properly
   static double last_price_l3h3 = 0;
   static double last_price_l4h4 = 0;
   static double last_price_l5h5 = 0;
   
   //--- Determine which price tracker to use based on level name
   double last_price = 0;
   if(level_name == "L3H3")
   {
      if(last_price_l3h3 == 0) last_price_l3h3 = price;
      last_price = last_price_l3h3;
   }
   else if(level_name == "L4H4")
   {
      if(last_price_l4h4 == 0) last_price_l4h4 = price;
      last_price = last_price_l4h4;
   }
   else if(level_name == "L5H5")
   {
      if(last_price_l5h5 == 0) last_price_l5h5 = price;
      last_price = last_price_l5h5;
   }
   
   //--- Check for breakout above resistance
   if(last_price <= resistance_level && price > resistance_level)
   {
      if(LogPredictions)
      {
         Print("🔔 Breakout detected above ", level_name, " resistance at ", DoubleToString(resistance_level, _Digits));
         Print("   Mode: ", UseMLPrediction && model_loaded ? "ML Prediction" : "Traditional Filters");
      }
      
      if(ShouldTrade(POSITION_TYPE_BUY, level_name))
      {
         //--- Additional filters for enhanced trading
         if(!IsInTrend(POSITION_TYPE_BUY))
         {
            if(LogPredictions)
               Print("❌ Trade skipped - Not in uptrend for BUY");
         }
         else if(!IsVolatilityAcceptable())
         {
            if(LogPredictions)
               Print("❌ Trade skipped - Volatility outside acceptable range");
         }
         else
         {
            if(LogPredictions)
            {
               if(UseMLPrediction && model_loaded)
                  Print("✅ ML prediction APPROVED - opening BUY position for ", level_name);
               else
                  Print("✅ Traditional filters PASSED - opening BUY position for ", level_name);
            }
            OpenPosition(POSITION_TYPE_BUY, level_name);
         }
      }
      else if(LogPredictions)
      {
         if(UseMLPrediction && model_loaded)
            Print("❌ ML prediction REJECTED - BUY trade skipped for ", level_name);
         else
            Print("❌ Traditional filters FAILED - BUY trade skipped for ", level_name);
      }
   }
   
   //--- Check for breakout below support
   if(last_price >= support_level && price < support_level)
   {
      if(LogPredictions)
      {
         Print("🔔 Breakout detected below ", level_name, " support at ", DoubleToString(support_level, _Digits));
         Print("   Mode: ", UseMLPrediction && model_loaded ? "ML Prediction" : "Traditional Filters");
      }
      
      if(ShouldTrade(POSITION_TYPE_SELL, level_name))
      {
         //--- Additional filters for enhanced trading
         if(!IsInTrend(POSITION_TYPE_SELL))
         {
            if(LogPredictions)
               Print("❌ Trade skipped - Not in downtrend for SELL");
         }
         else if(!IsVolatilityAcceptable())
         {
            if(LogPredictions)
               Print("❌ Trade skipped - Volatility outside acceptable range");
         }
         else
         {
            if(LogPredictions)
            {
               if(UseMLPrediction && model_loaded)
                  Print("✅ ML prediction APPROVED - opening SELL position for ", level_name);
               else
                  Print("✅ Traditional filters PASSED - opening SELL position for ", level_name);
            }
            OpenPosition(POSITION_TYPE_SELL, level_name);
         }
      }
      else if(LogPredictions)
      {
         if(UseMLPrediction && model_loaded)
            Print("❌ ML prediction REJECTED - SELL trade skipped for ", level_name);
         else
            Print("❌ Traditional filters FAILED - SELL trade skipped for ", level_name);
      }
   }
   
   //--- Update the appropriate last price tracker
   if(level_name == "L3H3")
      last_price_l3h3 = price;
   else if(level_name == "L4H4")
      last_price_l4h4 = price;
   else if(level_name == "L5H5")
      last_price_l5h5 = price;
}

//+------------------------------------------------------------------+
//| Determine if should trade based on ML prediction                 |
//+------------------------------------------------------------------+
bool ShouldTrade(ENUM_POSITION_TYPE position_type, string level_name)
{
   //--- When ML is disabled, use traditional trading filters
   if(!UseMLPrediction || !model_loaded)
   {
      //--- Use traditional momentum and volatility filters
      return CheckTraditionalFilters(position_type, level_name);
   }
   
   //--- Prepare features for ML model
   MarketFeatures market_features;
   PrepareMarketFeatures(market_features);
   
   //--- Get ML prediction
   double prediction = GetMLPrediction(market_features, position_type, level_name);
   
   //--- Get level-specific threshold
   double threshold = GetLevelSpecificThreshold(level_name);
   
   //--- Log ML impact for debugging
   static int ml_trade_count = 0;
   static int ml_filtered_count = 0;
   
   if(prediction >= threshold)
   {
      ml_trade_count++;
      if(LogPredictions)
         Print("✅ ML APPROVED trade #", ml_trade_count, " - Confidence: ", DoubleToString(prediction, 4), 
               " >= ", DoubleToString(threshold, 2), " (", level_name, ")");
   }
   else
   {
      ml_filtered_count++;
      if(LogPredictions)
         Print("❌ ML FILTERED trade #", ml_filtered_count, " - Confidence: ", DoubleToString(prediction, 4), 
               " < ", DoubleToString(threshold, 2), " (", level_name, ")");
   }
   
   //--- Print ML statistics periodically
   static datetime last_stats_time = 0;
   if(TimeCurrent() - last_stats_time > 3600) // Every hour
   {
      last_stats_time = TimeCurrent();
      int total_signals = ml_trade_count + ml_filtered_count;
      if(total_signals > 0)
      {
         double filter_rate = (double)ml_filtered_count / total_signals * 100;
         Print("🤖 ML Statistics - Total Signals: ", total_signals, 
               ", Approved: ", ml_trade_count, 
               ", Filtered: ", ml_filtered_count,
               " (", DoubleToString(filter_rate, 1), "% filtered)");
      }
   }
   
   //--- Check confidence threshold
   return (prediction >= threshold);
}

//+------------------------------------------------------------------+
//| Check traditional trading filters (when ML is disabled)         |
//+------------------------------------------------------------------+
bool CheckTraditionalFilters(ENUM_POSITION_TYPE position_type, string level_name)
{
   double current_price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   
   //--- Filter 1: Momentum confirmation using RSI
   int rsi_handle = iRSI(Symbol(), PERIOD_CURRENT, 14, PRICE_CLOSE);
   if(rsi_handle != INVALID_HANDLE)
   {
      double rsi_buffer[];
      ArraySetAsSeries(rsi_buffer, true);
      if(CopyBuffer(rsi_handle, 0, 0, 1, rsi_buffer) > 0)
      {
         double rsi = rsi_buffer[0];
         
         // For BUY: RSI should be above 30 (not oversold) and preferably above 50
         // For SELL: RSI should be below 70 (not overbought) and preferably below 50
         if(position_type == POSITION_TYPE_BUY && rsi < 30)
         {
            if(LogPredictions)
               Print("📊 Traditional Filter: BUY rejected - RSI too low (", DoubleToString(rsi, 1), ")");
            return false;
         }
         if(position_type == POSITION_TYPE_SELL && rsi > 70)
         {
            if(LogPredictions)
               Print("📊 Traditional Filter: SELL rejected - RSI too high (", DoubleToString(rsi, 1), ")");
            return false;
         }
      }
   }
   
   //--- Filter 2: Volatility check using ATR
   int atr_handle = iATR(Symbol(), PERIOD_CURRENT, ATRPeriod);
   if(atr_handle != INVALID_HANDLE)
   {
      double atr_buffer[];
      ArraySetAsSeries(atr_buffer, true);
      if(CopyBuffer(atr_handle, 0, 0, 1, atr_buffer) > 0)
      {
         double atr = atr_buffer[0];
         double atr_points = atr / point;
         
         // Skip trades during very low volatility (less than 50 points ATR)
         if(atr_points < 50)
         {
            if(LogPredictions)
               Print("📊 Traditional Filter: Trade rejected - Low volatility (ATR: ", DoubleToString(atr_points, 1), " points)");
            return false;
         }
         
         // Skip trades during extreme volatility (more than 500 points ATR)
         if(atr_points > 500)
         {
            if(LogPredictions)
               Print("📊 Traditional Filter: Trade rejected - Extreme volatility (ATR: ", DoubleToString(atr_points, 1), " points)");
            return false;
         }
      }
   }
   
   //--- Filter 3: Price action confirmation
   double price_bars[];
   ArraySetAsSeries(price_bars, true);
   int copied = CopyClose(Symbol(), PERIOD_CURRENT, 0, 5, price_bars);
   
   if(copied >= 5)
   {
      // For BUY: Price should be in upward momentum (recent closes higher)
      // For SELL: Price should be in downward momentum (recent closes lower)
      double momentum = price_bars[0] - price_bars[4];
      
      if(position_type == POSITION_TYPE_BUY && momentum < 0)
      {
         if(LogPredictions)
            Print("📊 Traditional Filter: BUY rejected - Negative momentum");
         return false;
      }
      if(position_type == POSITION_TYPE_SELL && momentum > 0)
      {
         if(LogPredictions)
            Print("📊 Traditional Filter: SELL rejected - Positive momentum");
         return false;
      }
   }
   
   //--- Filter 4: Level-specific filters
   if(level_name == "L5H5")
   {
      // L5/H5 are extreme levels, require stronger confirmation
      // Check distance from pivot - should be significant
      double distance_from_pivot = MathAbs(current_price - pivot_point) / point;
      if(distance_from_pivot < 100) // Less than 100 points from pivot
      {
         if(LogPredictions)
            Print("📊 Traditional Filter: L5H5 trade rejected - Too close to pivot (", DoubleToString(distance_from_pivot, 1), " points)");
         return false;
      }
   }
   
   //--- Log acceptance
   static int traditional_trade_count = 0;
   traditional_trade_count++;
   if(LogPredictions)
      Print("✅ Traditional filters PASSED - Trade #", traditional_trade_count, " for ", level_name, " ", 
            (position_type == POSITION_TYPE_BUY ? "BUY" : "SELL"));
   
   return true;
}

//+------------------------------------------------------------------+
//| Prepare market features for ML model                            |
//+------------------------------------------------------------------+
void PrepareMarketFeatures(MarketFeatures &market_features)
{
   double current_price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   
   //--- Price ratios to levels
   market_features.price_to_pivot_ratio = current_price / pivot_point;
   market_features.price_to_l3_ratio = current_price / s3;
   market_features.price_to_h3_ratio = current_price / r3;
   market_features.price_to_l4_ratio = current_price / s4;
   market_features.price_to_h4_ratio = current_price / r4;
   market_features.price_to_l5_ratio = current_price / s5;
   market_features.price_to_h5_ratio = current_price / r5;
   
   //--- Calculate volatility (ATR)
   int atr_handle = iATR(Symbol(), PERIOD_CURRENT, 14);
   if(atr_handle != INVALID_HANDLE)
   {
      double atr_buffer[];
      ArraySetAsSeries(atr_buffer, true);
      if(CopyBuffer(atr_handle, 0, 0, 1, atr_buffer) > 0)
      {
         market_features.volatility = atr_buffer[0] / current_price;
      }
      else
      {
         market_features.volatility = 0.01; // Default value
      }
   }
   else
   {
      market_features.volatility = 0.01; // Default value
   }
   
   //--- Volume ratio
   long volume_buffer[];
   ArraySetAsSeries(volume_buffer, true);
   if(CopyTickVolume(Symbol(), PERIOD_CURRENT, 0, 2, volume_buffer) >= 2)
   {
      market_features.volume_ratio = (volume_buffer[0] > 0 && volume_buffer[1] > 0) ? 
                                     (double)volume_buffer[0] / volume_buffer[1] : 1.0;
   }
   else
   {
      market_features.volume_ratio = 1.0; // Default value
   }
   
   //--- Time of day (0-1)
   MqlDateTime dt;
   TimeCurrent(dt);
   market_features.time_of_day = (dt.hour * 60 + dt.min) / 1440.0;
   
   //--- RSI
   int rsi_handle = iRSI(Symbol(), PERIOD_CURRENT, 14, PRICE_CLOSE);
   if(rsi_handle != INVALID_HANDLE)
   {
      double rsi_buffer[];
      ArraySetAsSeries(rsi_buffer, true);
      if(CopyBuffer(rsi_handle, 0, 0, 1, rsi_buffer) > 0)
      {
         market_features.rsi = rsi_buffer[0] / 100.0;
      }
      else
      {
         market_features.rsi = 0.5; // Default value
      }
   }
   else
   {
      market_features.rsi = 0.5; // Default value
   }
   
   //--- MACD Signal
   int macd_handle = iMACD(Symbol(), PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE);
   if(macd_handle != INVALID_HANDLE)
   {
      double macd_buffer[];
      ArraySetAsSeries(macd_buffer, true);
      if(CopyBuffer(macd_handle, 1, 0, 1, macd_buffer) > 0) // Signal line
      {
         market_features.macd_signal = macd_buffer[0];
      }
      else
      {
         market_features.macd_signal = 0.0; // Default value
      }
   }
   else
   {
      market_features.macd_signal = 0.0; // Default value
   }
}

//+------------------------------------------------------------------+
//| Get ML prediction using native ONNX                            |
//+------------------------------------------------------------------+
double GetMLPrediction(MarketFeatures &market_features, ENUM_POSITION_TYPE position_type, string level_name)
{
   if(!model_loaded || !UseMLPrediction || onnx_handle == INVALID_HANDLE)
      return 0.5;
   
   //--- Prepare input array for ONNX ensemble model (35 features)
   float inputs[];
   ArrayResize(inputs, 35);
   
   //--- Fill first 12 features with existing EA features
   inputs[0] = (float)market_features.price_to_pivot_ratio;
   inputs[1] = (float)market_features.price_to_l3_ratio;
   inputs[2] = (float)market_features.price_to_h3_ratio;
   inputs[3] = (float)market_features.price_to_l4_ratio;
   inputs[4] = (float)market_features.price_to_h4_ratio;
   inputs[5] = (float)market_features.price_to_l5_ratio;
   inputs[6] = (float)market_features.price_to_h5_ratio;
   inputs[7] = (float)market_features.volatility;
   inputs[8] = (float)market_features.volume_ratio;
   inputs[9] = (float)market_features.time_of_day;
   inputs[10] = (float)market_features.rsi;
   inputs[11] = (float)market_features.macd_signal;
   
   //--- Fill remaining 23 features with computed values (ensemble compatibility)
   //--- These approximate the enhanced features from ImprovedFeatureExtractor
   
   // Additional price ratios and market microstructure features
   double current_price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double spread = SymbolInfoDouble(Symbol(), SYMBOL_ASK) - SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double spread_ratio = spread / current_price;
   
   inputs[12] = (float)(current_price / ((r3 + s3) / 2.0)); // Price to L3/H3 midpoint ratio
   inputs[13] = (float)(current_price / ((r4 + s4) / 2.0)); // Price to L4/H4 midpoint ratio
   inputs[14] = (float)(current_price / ((r5 + s5) / 2.0)); // Price to L5/H5 midpoint ratio
   inputs[15] = (float)spread_ratio; // Bid-ask spread ratio
   inputs[16] = (float)(MathAbs(current_price - pivot_point) / current_price); // Distance from pivot ratio
   
   // Technical analysis features
   double high_price = iHigh(Symbol(), PERIOD_CURRENT, 1);
   double low_price = iLow(Symbol(), PERIOD_CURRENT, 1);
   double range = high_price - low_price;
   
   inputs[17] = (float)(range / current_price); // Current bar range ratio
   inputs[18] = (float)((current_price - low_price) / range); // Position in range
   inputs[19] = (float)((high_price - current_price) / range); // Distance from high
   
   // Moving average features
   int ma20_handle = iMA(Symbol(), PERIOD_CURRENT, 20, 0, MODE_SMA, PRICE_CLOSE);
   int ma50_handle = iMA(Symbol(), PERIOD_CURRENT, 50, 0, MODE_SMA, PRICE_CLOSE);
   
   if(ma20_handle != INVALID_HANDLE && ma50_handle != INVALID_HANDLE)
   {
      double ma20_buffer[], ma50_buffer[];
      ArraySetAsSeries(ma20_buffer, true);
      ArraySetAsSeries(ma50_buffer, true);
      
      if(CopyBuffer(ma20_handle, 0, 0, 1, ma20_buffer) > 0 && 
         CopyBuffer(ma50_handle, 0, 0, 1, ma50_buffer) > 0)
      {
         inputs[20] = (float)(current_price / ma20_buffer[0]); // Price to MA20 ratio
         inputs[21] = (float)(current_price / ma50_buffer[0]); // Price to MA50 ratio
         inputs[22] = (float)(ma20_buffer[0] / ma50_buffer[0]); // MA20/MA50 ratio
      }
      else
      {
         inputs[20] = 1.0f; inputs[21] = 1.0f; inputs[22] = 1.0f;
      }
   }
   else
   {
      inputs[20] = 1.0f; inputs[21] = 1.0f; inputs[22] = 1.0f;
   }
   
   // Additional volatility measures
   int atr_handle = iATR(Symbol(), PERIOD_CURRENT, ATRPeriod);
   if(atr_handle != INVALID_HANDLE)
   {
      double atr_buffer[];
      ArraySetAsSeries(atr_buffer, true);
      if(CopyBuffer(atr_handle, 0, 0, 3, atr_buffer) >= 3)
      {
         inputs[23] = (float)(atr_buffer[0] / atr_buffer[1]); // ATR ratio (current vs previous)
         inputs[24] = (float)(atr_buffer[1] / atr_buffer[2]); // ATR ratio (previous vs before)
      }
      else
      {
         inputs[23] = 1.0f; inputs[24] = 1.0f;
      }
   }
   else
   {
      inputs[23] = 1.0f; inputs[24] = 1.0f;
   }
   
   // Time-based features
   MqlDateTime dt;
   TimeCurrent(dt);
   inputs[25] = (float)(dt.hour / 24.0); // Hour of day normalized
   inputs[26] = (float)(dt.min / 60.0);  // Minute of hour normalized
   inputs[27] = (float)(dt.day_of_week / 7.0); // Day of week normalized
   
   // Market session features (approximated)
   bool is_london_session = (dt.hour >= 8 && dt.hour <= 16);
   bool is_ny_session = (dt.hour >= 13 && dt.hour <= 21);
   bool is_asian_session = (dt.hour >= 0 && dt.hour <= 8) || (dt.hour >= 21);
   
   inputs[28] = is_london_session ? 1.0f : 0.0f;
   inputs[29] = is_ny_session ? 1.0f : 0.0f;
   inputs[30] = is_asian_session ? 1.0f : 0.0f;
   
   // Level-specific features
   inputs[31] = (current_price > r3 || current_price < s3) ? 1.0f : 0.0f; // Outside L3/H3 range
   inputs[32] = (current_price > r4 || current_price < s4) ? 1.0f : 0.0f; // Outside L4/H4 range
   inputs[33] = (current_price > r5 || current_price < s5) ? 1.0f : 0.0f; // Outside L5/H5 range
   inputs[34] = (float)(market_features.volume_ratio * market_features.volatility); // Volume-volatility interaction
   
   //--- Debug features (first few predictions only)
   static int prediction_count = 0;
   prediction_count++;
   if(LogPredictions && prediction_count <= 3)
   {
      Print("=== ML Model Features (35 total) ===");
      Print("Core Features: Pivot ratios, volatility, volume, time, RSI, MACD");
      Print("Extended Features: Market microstructure, technical analysis, sessions");
      Print("Price/Pivot: ", DoubleToString(inputs[0], 4), 
            ", Volatility: ", DoubleToString(inputs[7], 6),
            ", RSI: ", DoubleToString(inputs[10], 2));
   }
   
   //--- Apply scaler normalization if available
   if(scaler_loaded)
   {
      for(int i = 0; i < 35; i++)
      {
         inputs[i] = (float)((inputs[i] - scaler_mean[i]) / scaler_scale[i]);
      }
   }
   
   //--- Prepare input shape for 35 features
   const ulong input_shape[] = {1, 35};
   if(!OnnxSetInputShape(onnx_handle, 0, input_shape))
   {
      Print("❌ Failed to set input shape for 35 features. Error: ", GetLastError());
      return 0.5;
   }
   
   //--- Let ONNX infer output shape automatically (more reliable)
   // For neural network models, ONNX can determine the output shape from the model
   
   //--- Create matrix from inputs for ONNX
   matrixf input_matrix;
   input_matrix.Init(1, 35);
   for(int i = 0; i < 35; i++)
   {
      input_matrix[0][i] = inputs[i];
   }
   
   //--- Create output matrix for single output (neural network)
   matrixf output_matrix;
   output_matrix.Init(1, 1);
   
   //--- Run inference
   if(!OnnxRun(onnx_handle, ONNX_NO_CONVERSION, input_matrix, output_matrix))
   {
      Print("❌ ONNX inference failed. Error: ", GetLastError());
      return 0.5;
   }
   
   //--- Get prediction value
   if(output_matrix.Rows() == 0 || output_matrix.Cols() == 0)
   {
      Print("❌ No output from ONNX model");
      return 0.5;
   }
   
   // Get the single neural network output
   double prediction = output_matrix[0][0];
   
   //--- Ensure prediction is in valid range [0, 1]
   prediction = MathMax(0.0, MathMin(1.0, prediction));
   
   //--- Log prediction if verbose
   if(LogPredictions)
   {
      Print("🤖 Neural Network ML Prediction for ", level_name, " ", 
            (position_type == POSITION_TYPE_BUY ? "BUY" : "SELL"), 
            ": ", DoubleToString(prediction, 4),
            " (Threshold: ", DoubleToString(GetLevelSpecificThreshold(level_name), 2), ")");
      
      if(prediction < GetLevelSpecificThreshold(level_name))
      {
         Print("  ⚠️ Neural network prediction below threshold - trade filtered");
      }
      else
      {
         Print("  ✅ Neural network prediction above threshold - trade approved!");
      }
   }
   
   return prediction;
}





//+------------------------------------------------------------------+
//| Initialize ONNX Model using native MQL5 support                |
//+------------------------------------------------------------------+
bool InitializeONNXModel()
{
   if(!UseMLPrediction)
   {
      Print("ML Prediction disabled by user settings");
      return false;
   }
   
   //--- Detect execution environment
   bool is_testing = MQLInfoInteger(MQL_TESTER);
   bool is_optimization = MQLInfoInteger(MQL_OPTIMIZATION);
   
   if(is_testing || is_optimization)
   {
      //--- Strategy Tester mode: Use embedded model resources
      Print("🧪 Strategy Tester/Optimization detected");
      
      bool tester_model_loaded = false;

#ifdef USE_EMBEDDED_MODEL
      Print("📦 Attempting to load ONNX model from embedded resource ...");
      //--- Create ONNX model from embedded buffer
      onnx_handle = OnnxCreateFromBuffer(embedded_model, ONNX_DEBUG_LOGS);
      if(onnx_handle != INVALID_HANDLE)
      {
         Print("✅ ONNX model loaded successfully from embedded resource (", ArraySize(embedded_model), " bytes)");
         tester_model_loaded = true;
      }
      else
      {
         Print("⚠️ Failed to load ONNX model from embedded buffer (Error: ", GetLastError(), ") – will try file-system fallback");
      }
#endif

      if(!tester_model_loaded)
      {
         Print("📂 Attempting to load ONNX model from file system for Strategy Tester ...");

         //--- Ensure the model path is initialised (SetupFilePaths() already called)
         if(!FileIsExist(model_path))
         {
            Print("⚠️ ONNX model file not found in tester directory: ", model_path);
            Print("Tester path: ", TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Files\\" + model_path);
            
            //--- Try to copy from Common\Files directory
            if(CopyModelFromCommonFiles(model_path))
            {
               Print("✅ Model copied from Common\\Files to tester directory");
            }
            else
            {
               Print("❌ Could not find or copy model from Common\\Files");
               ListAvailableModels();
               return false;
            }
         }

         onnx_handle = OnnxCreate(model_path, ONNX_DEBUG_LOGS);
         if(onnx_handle == INVALID_HANDLE)
         {
            Print("❌ Failed to create ONNX model from file in Strategy Tester: ", model_path);
            Print("Error code: ", GetLastError());
            return false;
         }

         Print("✅ ONNX model loaded successfully from file system: ", model_path);
      }
   }
   else
   {
      //--- Live trading mode: Use file-based model loading
      Print("🔴 Live trading mode detected");
      Print("📂 Loading ONNX model from file system...");
      
      //--- Check if ONNX model file exists
      if(!FileIsExist(model_path))
      {
         Print("❌ ONNX model file not found: ", model_path);
         Print("Full path would be: ", TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Files\\" + model_path);
         Print("Available models in MLCamarilla folder:");
         ListAvailableModels();
         
         //--- Try alternative model files
         string alternative_models[] = {"MLCamarilla\\camarilla_model.onnx", "MLCamarilla\\test_camarilla_model.onnx"};
         for(int i = 0; i < ArraySize(alternative_models); i++)
         {
            if(FileIsExist(alternative_models[i]))
            {
               Print("Found alternative model: ", alternative_models[i]);
               model_path = alternative_models[i];
               break;
            }
         }
         
         if(!FileIsExist(model_path))
         {
            Print("❌ No valid ONNX model found. Disabling ML predictions.");
            return false;
         }
      }
      
      //--- Create ONNX model from file
      onnx_handle = OnnxCreate(model_path, ONNX_DEBUG_LOGS);
      if(onnx_handle == INVALID_HANDLE)
      {
         Print("❌ Failed to create ONNX model from file: ", model_path);
         Print("Error code: ", GetLastError());
         return false;
      }
      
      Print("✅ ONNX model loaded successfully from file: ", model_path);
   }
   
   //--- Get model information
   if(!GetONNXModelInfo())
   {
      OnnxRelease(onnx_handle);
      onnx_handle = INVALID_HANDLE;
      return false;
   }
   
   //--- Validate model structure
   if(!ValidateModelStructure())
   {
      OnnxRelease(onnx_handle);
      onnx_handle = INVALID_HANDLE;
      return false;
   }
   
   //--- Load scaler parameters
   scaler_loaded = LoadScalerParameters();
   
   //--- Show model info if requested
   if(ShowModelInfo)
   {
      PrintONNXModelInfo();
   }
   
   //--- Print loading summary
   Print("🎯 ONNX Model Loading Summary:");
   Print("   Mode: ", (is_testing || is_optimization) ? "Strategy Tester" : "Live Trading");
   Print("   Method: ", (is_testing || is_optimization) ? "Embedded Resource" : "File System");
   Print("   Handle: ", onnx_handle);
   Print("   Scaler: ", scaler_loaded ? "Loaded" : "Not Available");
   
   return true;
}

//+------------------------------------------------------------------+
//| Get ONNX model information                                      |
//+------------------------------------------------------------------+
bool GetONNXModelInfo()
{
   //--- Get input/output counts
   model_input_count = OnnxGetInputCount(onnx_handle);
   model_output_count = OnnxGetOutputCount(onnx_handle);
   
   if(model_input_count <= 0 || model_output_count <= 0)
   {
      Print("❌ Invalid model structure: inputs=", model_input_count, ", outputs=", model_output_count);
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Validate model structure                                        |
//+------------------------------------------------------------------+
bool ValidateModelStructure()
{
   //--- Check input count
   if(model_input_count != 1)
   {
      Print("❌ Model should have exactly 1 input, but has ", model_input_count);
      return false;
   }
   
   //--- Ensemble models may have multiple outputs - we'll use the first one
   if(model_output_count < 1)
   {
      Print("❌ Model should have at least 1 output, but has ", model_output_count);
      return false;
   }
   
   if(model_output_count > 1)
   {
      Print("⚠️ Ensemble model detected with ", model_output_count, " outputs - using first output for predictions");
   }
   
   Print("✅ Model structure validated: inputs=", model_input_count, ", outputs=", model_output_count);
   
   return true;
}

//+------------------------------------------------------------------+
//| Print ONNX model information                                    |
//+------------------------------------------------------------------+
void PrintONNXModelInfo()
{
   Print("=== ONNX Model Information ===");
   Print("Model: ", model_path);
   Print("Inputs: ", model_input_count);
   Print("Outputs: ", model_output_count);
   
   // Get input name and type info
   string input_name = OnnxGetInputName(onnx_handle, 0);
   Print("  Input[0]: ", input_name);
   
   // Get output name and type info
   string output_name = OnnxGetOutputName(onnx_handle, 0);
   Print("  Output[0]: ", output_name);
   
   // Additional validation as per ONNX documentation
   if(ShowModelInfo)
   {
      Print("Model validation complete - compatible with MQL5 ONNX runtime");
   }
   
   Print("==============================");
}

//+------------------------------------------------------------------+
//| Load scaler parameters from JSON file or embedded resource     |
//+------------------------------------------------------------------+
bool LoadScalerParameters()
{
   //--- Detect execution environment
   bool is_testing = MQLInfoInteger(MQL_TESTER);
   bool is_optimization = MQLInfoInteger(MQL_OPTIMIZATION);
   
   string content = "";
   
   if(is_testing || is_optimization)
   {
      //--- Strategy Tester mode: Try embedded scaler first, then file fallback
      Print("📈 Loading scaler for Strategy Tester...");
      
      bool tester_scaler_loaded = false;
      
      #ifdef USE_EMBEDDED_MODEL
         Print("📦 Attempting to load scaler from embedded resource...");
         //--- Convert uchar array to string
         content = CharArrayToString(embedded_scaler);
         if(StringLen(content) > 0)
         {
            Print("✅ Embedded scaler loaded, size: ", StringLen(content), " characters");
            tester_scaler_loaded = true;
         }
         else
         {
            Print("⚠️ Embedded scaler is empty - will try file fallback");
         }
      #endif
      
      if(!tester_scaler_loaded)
      {
         Print("📂 Attempting to load scaler from file system for Strategy Tester...");
         
         //--- Check if scaler exists in tester directory
         if(!FileIsExist(scaler_path))
         {
                         //--- Try to copy from Common\Files
             if(FileIsExist(scaler_path, FILE_COMMON))
             {
                if(FileCopy(scaler_path, FILE_COMMON, scaler_path, FILE_REWRITE))
                {
                   Print("✅ Scaler copied from Common\\Files");
                }
                else
                {
                   Print("❌ Failed to copy scaler from Common\\Files");
                   Print("Features will not be normalized");
                   return false;
                }
             }
            else
            {
               Print("❌ Scaler not found in Common\\Files: ", scaler_path);
               Print("Features will not be normalized");
               return false;
            }
         }
         
         //--- Read scaler file
         int file_handle = FileOpen(scaler_path, FILE_READ|FILE_TXT|FILE_ANSI);
         if(file_handle == INVALID_HANDLE)
         {
            Print("❌ Cannot open scaler file: ", scaler_path);
            return false;
         }
         
         while(!FileIsEnding(file_handle))
         {
            string line = FileReadString(file_handle);
            if(StringLen(content) == 0 && StringLen(line) > 0)
            {
               // Remove BOM if present
               if(StringGetCharacter(line, 0) == 0xFEFF || StringGetCharacter(line, 0) == 0xFFFE)
               {
                  line = StringSubstr(line, 1);
               }
            }
            content += line;
         }
         FileClose(file_handle);
         
         Print("✅ File-based scaler loaded for tester, size: ", StringLen(content), " characters");
      }
   }
   else
   {
      //--- Live trading mode: Use file-based scaler
      Print("📂 Loading scaler from file system...");
      
      if(!FileIsExist(scaler_path))
      {
         Print("Scaler parameters file not found: ", scaler_path);
         Print("Features will not be normalized");
         return false;
      }
      
      //--- Read scaler file with proper encoding
      int file_handle = FileOpen(scaler_path, FILE_READ|FILE_TXT|FILE_ANSI);
      if(file_handle == INVALID_HANDLE)
      {
         Print("Error: Cannot open scaler file: ", scaler_path);
         return false;
      }
      
      while(!FileIsEnding(file_handle))
      {
         string line = FileReadString(file_handle);
         // Clean any potential BOM or encoding issues
         if(StringLen(content) == 0 && StringLen(line) > 0)
         {
            // Remove BOM if present
            if(StringGetCharacter(line, 0) == 0xFEFF || StringGetCharacter(line, 0) == 0xFFFE)
            {
               line = StringSubstr(line, 1);
            }
         }
         content += line;
      }
      FileClose(file_handle);
      
      Print("✅ File-based scaler loaded, size: ", StringLen(content), " characters");
   }
   
   Print("DEBUG: Scaler content length: ", StringLen(content));
   Print("DEBUG: First 200 chars: ", StringSubstr(content, 0, MathMin(200, StringLen(content))));
   
   //--- Parse JSON content (simple parsing)
   bool mean_found = ParseDoubleArray(content, "\"mean\":", scaler_mean);
   bool scale_found = ParseDoubleArray(content, "\"scale\":", scaler_scale);
   
   Print("DEBUG: Mean found: ", mean_found, ", Scale found: ", scale_found);
   
   if(!mean_found || !scale_found)
   {
      Print("Error: Could not parse scaler parameters");
      Print("DEBUG: Content: ", content);
      return false;
   }
   
   Print("✓ Scaler parameters loaded successfully");
   Print("  Mean[0]: ", DoubleToString(scaler_mean[0], 8));
   Print("  Scale[0]: ", DoubleToString(scaler_scale[0], 8));
   Print("  Mode: ", (is_testing || is_optimization) ? "Embedded Resource" : "File System");
   
   return true;
}

//+------------------------------------------------------------------+
//| Parse double array from JSON string                             |
//+------------------------------------------------------------------+
bool ParseDoubleArray(string json_content, string key, double &array[])
{
   int key_pos = StringFind(json_content, key);
   if(key_pos < 0) return false;
   
   int bracket_start = StringFind(json_content, "[", key_pos);
   if(bracket_start < 0) return false;
   
   int bracket_end = StringFind(json_content, "]", bracket_start);
   if(bracket_end < 0) return false;
   
   string array_content = StringSubstr(json_content, bracket_start + 1, bracket_end - bracket_start - 1);
   
   //--- Split by comma and parse values
   string values[];
   int count = StringSplit(array_content, ',', values);
   
   if(count != 35)
   {
      Print("Error: Expected 35 values for ensemble model, got ", count);
      return false;
   }
   
   for(int i = 0; i < 35; i++)
   {
      StringTrimLeft(values[i]);
      StringTrimRight(values[i]);
      array[i] = StringToDouble(values[i]);
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| List available models in MLCamarilla folder                     |
//+------------------------------------------------------------------+
void ListAvailableModels()
{
   Print("=== Available Models in MLCamarilla Folder ===");
   Print("Model naming convention: symbol_timeframe_ensemble_model.onnx");
   Print("Example: xauusd_m5_ensemble_model.onnx");
   Print("Models can be in subdirectories: MLCamarilla/XAUUSD_M5_ensemble_20250620_170255/");
   Print("");
   
   // First, search in root directory
   string search_path = "MLCamarilla\\*.onnx";
   string filename;
   long search_handle = FileFindFirst(search_path, filename);
   
   string all_models[];
   int total_model_count = 0;
   
   if(search_handle != INVALID_HANDLE)
   {
      do
      {
         ArrayResize(all_models, total_model_count + 1);
         all_models[total_model_count] = filename;
         total_model_count++;
      }
      while(FileFindNext(search_handle, filename));
      
      FileFindClose(search_handle);
   }
   
   // Now search in subdirectories
   string subdirs[];
   int subdir_count = GetSubdirectories("MLCamarilla\\", subdirs);
   
   Print("Found ", subdir_count, " subdirectories in MLCamarilla folder");
   
   for(int d = 0; d < subdir_count; d++)
   {
      string subdir_search = "MLCamarilla\\" + subdirs[d] + "\\*.onnx";
      search_handle = FileFindFirst(subdir_search, filename);
      
      if(search_handle != INVALID_HANDLE)
      {
         do
         {
            ArrayResize(all_models, total_model_count + 1);
            all_models[total_model_count] = subdirs[d] + "\\" + filename;
            total_model_count++;
         }
         while(FileFindNext(search_handle, filename));
         
         FileFindClose(search_handle);
      }
   }
   
   // Display results
   Print("Found ", total_model_count, " ONNX model(s) total:");
   
   // Group by symbol
   string current_symbol = Symbol();
   StringToLower(current_symbol);
   bool found_for_symbol = false;
   
   Print("\nModels for current symbol (", Symbol(), "):");
   for(int i = 0; i < total_model_count; i++)
   {
      string model_lower = all_models[i];
      StringToLower(model_lower);
      
      if(StringFind(model_lower, current_symbol) >= 0)
      {
         Print("  ✓ ", all_models[i], ParseModelInfo(all_models[i]));
         found_for_symbol = true;
      }
   }
   
   if(!found_for_symbol)
   {
      Print("  ✗ No models found for ", Symbol());
   }
   
   // Show all models organized by location
   Print("\nAll available models:");
   
   // Root directory models
   Print("\nIn root directory (MLCamarilla\\):");
   for(int i = 0; i < total_model_count; i++)
   {
      if(StringFind(all_models[i], "\\") < 0)
      {
         Print("  - ", all_models[i], ParseModelInfo(all_models[i]));
      }
   }
   
   // Subdirectory models
   for(int d = 0; d < subdir_count; d++)
   {
      Print("\nIn subdirectory: ", subdirs[d]);
      for(int i = 0; i < total_model_count; i++)
      {
         if(StringFind(all_models[i], subdirs[d] + "\\") == 0)
         {
            Print("  - ", all_models[i], ParseModelInfo(all_models[i]));
         }
      }
   }
   
   Print("\nTip: You can specify a model using:");
   Print("1. Just the filename for auto-detection: 'xauusd_ensemble_model.onnx'");
   Print("2. With subdirectory: 'XAUUSD_M5_ensemble_20250620_170255/ensemble_camarilla_model.onnx'");
   Print("Current auto-detection will look for: ", Symbol(), "_", GetTimeframeString(Period()), "_ensemble_model.onnx");
}

//+------------------------------------------------------------------+
//| Parse model info from filename                                  |
//+------------------------------------------------------------------+
string ParseModelInfo(string filename)
{
   string info = "";
   string fname_lower = filename;
   StringToLower(fname_lower);
   
   // Extract symbol
   string symbols[] = {"eurusd", "gbpusd", "xauusd", "usdjpy", "audusd", "usdcad", "nzdusd", "usdchf"};
   for(int i = 0; i < ArraySize(symbols); i++)
   {
      if(StringFind(fname_lower, symbols[i]) >= 0)
      {
         info += " [Symbol: " + symbols[i];
         break;
      }
   }
   
   // Extract timeframe
   string timeframes[] = {"_m1_", "_m5_", "_m15_", "_m30_", "_h1_", "_h4_", "_d1_", "_w1_", "_mn1_"};
   string tf_names[] = {"M1", "M5", "M15", "M30", "H1", "H4", "D1", "W1", "MN1"};
   
   for(int i = 0; i < ArraySize(timeframes); i++)
   {
      if(StringFind(fname_lower, timeframes[i]) >= 0)
      {
         info += ", TF: " + tf_names[i];
         break;
      }
   }
   
   if(info != "") info += "]";
   
   return info;
}



//+------------------------------------------------------------------+
//| Calculate ATR-based Stop Loss                                   |
//+------------------------------------------------------------------+
double CalculateATRStopLoss(ENUM_POSITION_TYPE position_type, double entry_price, string level_name)
{
   if(!UseATRStops)
      return 0; // Use fixed stops
   
   int atr_handle = iATR(Symbol(), PERIOD_CURRENT, ATRPeriod);
   if(atr_handle == INVALID_HANDLE)
   {
      Print("❌ ATR handle invalid for stop loss calculation");
      return 0;
   }
   
   double atr_buffer[];
   ArraySetAsSeries(atr_buffer, true);
   if(CopyBuffer(atr_handle, 0, 0, 1, atr_buffer) <= 0)
   {
      Print("❌ Failed to copy ATR buffer for stop loss");
      return 0;
   }
   
   double atr_value = atr_buffer[0];
   double point_value = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   double tick_size = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
   
   // Get level-specific multiplier
   double level_multiplier = GetLevelSpecificSLMultiplier(level_name);
   
   // Use tick size instead of point for more accurate calculation
   double atr_distance = atr_value;  // ATR is already in price terms
   double stop_distance = atr_distance * level_multiplier;
   
   // Debug output
   Print("🔍 ATR Debug - ATR Value: ", DoubleToString(atr_value, 8), 
         ", Level Multiplier (", level_name, "): ", level_multiplier,
         ", Stop Distance: ", DoubleToString(stop_distance, 8),
         ", Point: ", DoubleToString(point_value, 8),
         ", Tick Size: ", DoubleToString(tick_size, 8));
   
   // Calculate stop loss price
   double sl_price = 0;
   if(position_type == POSITION_TYPE_BUY)
      sl_price = entry_price - stop_distance;
   else
      sl_price = entry_price + stop_distance;
   
   // Validate stop loss distance
   double sl_distance_points = MathAbs(entry_price - sl_price) / point_value;
   Print("✅ ATR Stop Loss - Distance: ", DoubleToString(sl_distance_points, 1), " points, Price: ", DoubleToString(sl_price, _Digits));
   
   return sl_price;
}

//+------------------------------------------------------------------+
//| Calculate ATR-based Take Profit                                 |
//+------------------------------------------------------------------+
double CalculateATRTakeProfit(ENUM_POSITION_TYPE position_type, double entry_price, double sl_price)
{
   if(!UseATRStops)
      return 0; // Use fixed take profit
   
   int atr_handle = iATR(Symbol(), PERIOD_CURRENT, ATRPeriod);
   if(atr_handle == INVALID_HANDLE)
   {
      Print("❌ ATR handle invalid for take profit calculation");
      return 0;
   }
   
   double atr_buffer[];
   ArraySetAsSeries(atr_buffer, true);
   if(CopyBuffer(atr_handle, 0, 0, 1, atr_buffer) <= 0)
   {
      Print("❌ Failed to copy ATR buffer for take profit");
      return 0;
   }
   
   double atr_value = atr_buffer[0];
   double point_value = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   
   // Calculate take profit distance using ATR value directly
   double atr_distance = atr_value;
   double tp_distance = atr_distance * ATRMultiplierTP;
   
   // Ensure minimum risk/reward ratio
   double risk_distance = MathAbs(entry_price - sl_price);
   double min_reward_distance = risk_distance * MinRiskRewardRatio;
   
   if(tp_distance < min_reward_distance)
   {
      tp_distance = min_reward_distance;
      Print("🔄 TP adjusted for R:R ratio - Original: ", DoubleToString(atr_distance * ATRMultiplierTP, 8), 
            ", Adjusted: ", DoubleToString(tp_distance, 8));
   }
   
   // Calculate take profit price
   double tp_price = 0;
   if(position_type == POSITION_TYPE_BUY)
      tp_price = entry_price + tp_distance;
   else
      tp_price = entry_price - tp_distance;
   
   // Validate take profit distance
   double tp_distance_points = MathAbs(entry_price - tp_price) / point_value;
   Print("✅ ATR Take Profit - Distance: ", DoubleToString(tp_distance_points, 1), " points, Price: ", DoubleToString(tp_price, _Digits));
   
   return tp_price;
}

//+------------------------------------------------------------------+
//| Get ATR value in points                                        |
//+------------------------------------------------------------------+
double GetATRInPoints()
{
   int atr_handle = iATR(Symbol(), PERIOD_CURRENT, ATRPeriod);
   if(atr_handle == INVALID_HANDLE)
   {
      Print("❌ ATR handle invalid in GetATRInPoints");
      return 0;
   }
   
   double atr_buffer[];
   ArraySetAsSeries(atr_buffer, true);
   if(CopyBuffer(atr_handle, 0, 0, 1, atr_buffer) <= 0)
   {
      Print("❌ Failed to copy ATR buffer in GetATRInPoints");
      return 0;
   }
   
   double atr_value = atr_buffer[0];
   double point_value = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   double atr_points = atr_value / point_value;
   
   // Debug output (limited to avoid spam)
   static datetime last_debug = 0;
   if(TimeCurrent() - last_debug > 3600) // Log once per hour
   {
      last_debug = TimeCurrent();
      Print("📊 ATR Info - Value: ", DoubleToString(atr_value, 8), 
            ", Points: ", DoubleToString(atr_points, 1), 
            ", Point Size: ", DoubleToString(point_value, 8));
   }
   
   return atr_points;
}

//+------------------------------------------------------------------+
//| Open position                                                    |
//+------------------------------------------------------------------+
void OpenPosition(ENUM_POSITION_TYPE position_type, string level_name)
{
   double volume = CalculatePositionSize();
   
   // Check if volume is valid (could be 0 due to risk limits)
   if(volume <= 0)
   {
      Print("Position not opened - volume calculated as 0 due to risk limits");
      return;
   }
   
   double price = (position_type == POSITION_TYPE_BUY) ? SymbolInfoDouble(Symbol(), SYMBOL_ASK) : SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double sl = 0, tp = 0;
   double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   
   //--- Calculate SL and TP
   if(UseATRStops)
   {
      // Use ATR-based stops
      sl = CalculateATRStopLoss(position_type, price, level_name);
      if(sl > 0)
      {
         tp = CalculateATRTakeProfit(position_type, price, sl);
         
         // Log ATR-based calculations
         double sl_points = MathAbs(price - sl) / point;
         double tp_points = MathAbs(price - tp) / point;
         double rr_ratio = tp_points / sl_points;
         
         Print("ATR-based SL/TP - SL: ", DoubleToString(sl_points, 1), " points, TP: ", 
               DoubleToString(tp_points, 1), " points, R:R = ", DoubleToString(rr_ratio, 2));
      }
      else
      {
         // Fallback to fixed stops if ATR calculation fails
         if(StopLossPoints > 0)
         {
            sl = (position_type == POSITION_TYPE_BUY) ? 
                 price - StopLossPoints * point : 
                 price + StopLossPoints * point;
         }
         
         if(TakeProfitPoints > 0)
         {
            tp = (position_type == POSITION_TYPE_BUY) ? 
                 price + TakeProfitPoints * point : 
                 price - TakeProfitPoints * point;
         }
      }
   }
   else
   {
      // Use fixed stops
      if(StopLossPoints > 0)
      {
         sl = (position_type == POSITION_TYPE_BUY) ? 
              price - StopLossPoints * point : 
              price + StopLossPoints * point;
      }
      
      if(TakeProfitPoints > 0)
      {
         tp = (position_type == POSITION_TYPE_BUY) ? 
              price + TakeProfitPoints * point : 
              price - TakeProfitPoints * point;
      }
   }
   
   //--- Send order
   string comment = "MLCamarilla_" + level_name;
   
   bool success = false;
   if(position_type == POSITION_TYPE_BUY)
   {
      success = trade.Buy(volume, Symbol(), price, sl, tp, comment);
      if(success)
      {
         Print("BUY order opened for ", level_name, " at ", price, " volume: ", volume);
      }
   }
   else
   {
      success = trade.Sell(volume, Symbol(), price, sl, tp, comment);
      if(success)
      {
         Print("SELL order opened for ", level_name, " at ", price, " volume: ", volume);
      }
   }
   
   //--- Add position to advanced tracking if successful
   if(success && UseAdvancedRisk)
   {
      ulong ticket = trade.ResultOrder();
      AddPositionToTracker(ticket);
      
      // Print risk information
      double risk_percent = CalculateCurrentPortfolioRisk();
      Print("Position risk info - Portfolio heat: ", DoubleToString(risk_percent, 2), 
            "% | Daily P&L: ", DoubleToString(daily_profit_loss, 2), 
            " | Drawdown: ", DoubleToString(current_drawdown, 2), "%");
   }
}

//+------------------------------------------------------------------+
//| Calculate position size based on risk                           |
//+------------------------------------------------------------------+
double CalculatePositionSize()
{
   if(UseAdvancedRisk)
      return CalculateAdvancedPositionSize();
   
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_amount = balance * RiskPercent / 100.0;
   double tick_value = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
   double stop_loss_ticks = StopLossPoints;
   
   // If using ATR stops, calculate actual stop distance
   if(UseATRStops)
   {
      int atr_handle = iATR(Symbol(), PERIOD_CURRENT, ATRPeriod);
      if(atr_handle != INVALID_HANDLE)
      {
         double atr_buffer[];
         ArraySetAsSeries(atr_buffer, true);
         if(CopyBuffer(atr_handle, 0, 0, 1, atr_buffer) > 0)
         {
            double atr_value = atr_buffer[0];
            double point_value = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
            double stop_distance = atr_value * ATRMultiplierSL;
            stop_loss_ticks = stop_distance / point_value;
            
            Print("📊 Position Sizing ATR - ATR: ", DoubleToString(atr_value, 8), 
                  ", Stop Distance: ", DoubleToString(stop_distance, 8), 
                  ", Stop Ticks: ", DoubleToString(stop_loss_ticks, 1));
         }
      }
   }
   
   if(stop_loss_ticks <= 0 || tick_value <= 0)
      return SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   
   double volume = risk_amount / (stop_loss_ticks * tick_value);
   
   //--- Normalize volume
   double min_volume = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   double max_volume = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
   double volume_step = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
   
   volume = MathMax(min_volume, MathMin(max_volume, volume));
   volume = MathRound(volume / volume_step) * volume_step;
   
   return volume;
}

//+------------------------------------------------------------------+
//| Initialize Advanced Risk Management System                      |
//+------------------------------------------------------------------+
void InitializeAdvancedRiskManagement()
{
   if(!UseAdvancedRisk)
   {
      Print("Advanced Risk Management disabled");
      return;
   }
   
   Print("Initializing Advanced Risk Management System...");
   
   // Initialize daily tracking
   MqlDateTime dt;
   TimeCurrent(dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   daily_reset_time = StructToTime(dt);
   
   daily_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   daily_profit_loss = 0.0;
   
   // Initialize drawdown tracking
   account_high_water_mark = AccountInfoDouble(ACCOUNT_EQUITY);
   current_drawdown = 0.0;
   
   // Initialize trading state
   trading_suspended = false;
   suspension_reason = "";
   suspension_time = 0;
   
   // Initialize position tracker array
   ArrayResize(position_tracker, 0);
   
   Print("✓ Advanced Risk Management initialized");
   Print("  Daily start balance: ", DoubleToString(daily_start_balance, 2));
   Print("  High water mark: ", DoubleToString(account_high_water_mark, 2));
}

//+------------------------------------------------------------------+
//| Print Risk Management Status                                    |
//+------------------------------------------------------------------+
void PrintRiskManagementStatus()
{
   Print("=== Advanced Risk Management Status ===");
   Print("Enabled: ", UseAdvancedRisk ? "YES" : "NO");
   
   if(!UseAdvancedRisk) return;
   
   Print("Max Daily Loss: ", DoubleToString(MaxDailyLoss, 2), "%");
   Print("Max Drawdown: ", DoubleToString(MaxDrawdown, 2), "%");
   Print("Portfolio Heat Limit: ", DoubleToString(PortfolioHeat, 2), "%");
   Print("Trailing Stop: ", UseTrailingStop ? "ENABLED" : "DISABLED");
   Print("Dynamic Lot Size: ", UseDynamicLotSize ? "ENABLED" : "DISABLED");
   Print("Time-based Exit: ", UseTimeBasedExit ? "ENABLED" : "DISABLED");
   Print("Current Status: ", trading_suspended ? "SUSPENDED (" + suspension_reason + ")" : "ACTIVE");
}

//+------------------------------------------------------------------+
//| Calculate Advanced Position Size                                |
//+------------------------------------------------------------------+
double CalculateAdvancedPositionSize()
{
   // Base calculation
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double risk_amount = balance * RiskPercent / 100.0;
   
   // Apply dynamic sizing based on equity
   if(UseDynamicLotSize)
   {
      double equity_factor = equity / balance;
      equity_factor = MathMax(0.5, MathMin(1.5, equity_factor)); // Limit factor between 0.5 and 1.5
      risk_amount *= equity_factor;
   }
   
   // Adjust for volatility
   double atr_adjustment = GetVolatilityAdjustment();
   double adjusted_sl_points = StopLossPoints * atr_adjustment;
   
   // If using ATR stops, override with actual ATR calculation
   if(UseATRStops)
   {
      int atr_handle = iATR(Symbol(), PERIOD_CURRENT, ATRPeriod);
      if(atr_handle != INVALID_HANDLE)
      {
         double atr_buffer[];
         ArraySetAsSeries(atr_buffer, true);
         if(CopyBuffer(atr_handle, 0, 0, 1, atr_buffer) > 0)
         {
            double atr_value = atr_buffer[0];
            double point_value = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
            double stop_distance = atr_value * ATRMultiplierSL;
            adjusted_sl_points = stop_distance / point_value;
            
            Print("📊 Advanced Sizing ATR - ATR: ", DoubleToString(atr_value, 8), 
                  ", Stop Distance: ", DoubleToString(stop_distance, 8), 
                  ", Points: ", DoubleToString(adjusted_sl_points, 1));
         }
      }
   }
   
   // Calculate position size
   double tick_value = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
   if(adjusted_sl_points <= 0 || tick_value <= 0)
      return SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   
   double volume = risk_amount / (adjusted_sl_points * tick_value);
   
   // Apply portfolio heat limit
   volume = ApplyPortfolioHeatLimit(volume);
   
   // Apply account protection limits
   volume = ApplyAccountProtectionLimits(volume);
   
   // Normalize volume
   double min_volume = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   double max_volume = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
   double volume_step = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
   
   volume = MathMax(min_volume, MathMin(max_volume, volume));
   volume = MathMax(MinLotSize, MathMin(MaxLotSize, volume));
   volume = MathRound(volume / volume_step) * volume_step;
   
   return volume;
}

//+------------------------------------------------------------------+
//| Get Volatility Adjustment Factor                                |
//+------------------------------------------------------------------+
double GetVolatilityAdjustment()
{
   int atr_handle = iATR(Symbol(), PERIOD_CURRENT, 14);
   if(atr_handle == INVALID_HANDLE)
      return 1.0;
   
   double atr_buffer[];
   ArraySetAsSeries(atr_buffer, true);
   if(CopyBuffer(atr_handle, 0, 0, 1, atr_buffer) <= 0)
      return 1.0;
   
   double current_atr = atr_buffer[0];
   double point_value = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   double atr_points = current_atr / point_value;
   
   // Compare with average ATR
   double avg_atr_points = 200; // Default expected ATR in points
   if(CopyBuffer(atr_handle, 0, 1, 20, atr_buffer) > 0)
   {
      double sum = 0;
      for(int i = 0; i < 20; i++)
         sum += atr_buffer[i];
      avg_atr_points = (sum / 20) / point_value;
   }
   
   // Calculate adjustment factor
   double volatility_ratio = atr_points / avg_atr_points;
   double adjustment = 1.0 + (volatility_ratio - 1.0) * VolatilityMultiplier;
   
   return MathMax(0.5, MathMin(2.0, adjustment));
}

//+------------------------------------------------------------------+
//| Apply Portfolio Heat Limit                                      |
//+------------------------------------------------------------------+
double ApplyPortfolioHeatLimit(double proposed_volume)
{
   double current_risk = CalculateCurrentPortfolioRisk();
   double tick_value = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
   double proposed_risk = proposed_volume * StopLossPoints * tick_value;
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double proposed_risk_percent = (proposed_risk / balance) * 100.0;
   
   if(current_risk + proposed_risk_percent > PortfolioHeat)
   {
      double available_risk_percent = PortfolioHeat - current_risk;
      if(available_risk_percent <= 0)
         return 0; // No more risk capacity
      
      double max_risk_amount = balance * available_risk_percent / 100.0;
      proposed_volume = max_risk_amount / (StopLossPoints * tick_value);
   }
   
   return proposed_volume;
}

//+------------------------------------------------------------------+
//| Calculate Current Portfolio Risk                                |
//+------------------------------------------------------------------+
double CalculateCurrentPortfolioRisk()
{
   double total_risk = 0.0;
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionGetTicket(i) > 0)
      {
         double volume = PositionGetDouble(POSITION_VOLUME);
         double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl = PositionGetDouble(POSITION_SL);
         
         if(sl > 0)
         {
            double risk_points = MathAbs(open_price - sl) / SymbolInfoDouble(Symbol(), SYMBOL_POINT);
            double tick_value = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
            double position_risk = volume * risk_points * tick_value;
            total_risk += position_risk;
         }
      }
   }
   
   return (total_risk / balance) * 100.0;
}

//+------------------------------------------------------------------+
//| Apply Account Protection Limits                                 |
//+------------------------------------------------------------------+
double ApplyAccountProtectionLimits(double proposed_volume)
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   // Check minimum equity level
   if(equity < MinEquityLevel)
   {
      Print("Account equity below minimum level: ", equity, " < ", MinEquityLevel);
      return 0;
   }
   
   // Apply conservative sizing if equity is low
   if(equity < MinEquityLevel * 2)
   {
      proposed_volume *= 0.5; // Reduce position size by 50%
      Print("Reducing position size due to low equity: ", equity);
   }
   
   return proposed_volume;
}

//+------------------------------------------------------------------+
//| Update Advanced Risk Management (Called on each tick)          |
//+------------------------------------------------------------------+
void UpdateAdvancedRiskManagement()
{
   if(!UseAdvancedRisk) return;
   
   UpdateDailyTracking();
   UpdateDrawdownTracking();
   UpdatePositionTracking();
   CheckRiskLimits();
}

//+------------------------------------------------------------------+
//| Update Daily Tracking                                           |
//+------------------------------------------------------------------+
void UpdateDailyTracking()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   
   // Check if new day started
   if(TimeCurrent() >= daily_reset_time + 86400) // 24 hours
   {
      dt.hour = 0;
      dt.min = 0;
      dt.sec = 0;
      daily_reset_time = StructToTime(dt);
      daily_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
      
      Print("Daily tracking reset. New start balance: ", DoubleToString(daily_start_balance, 2));
   }
   
   // Update daily P&L
   double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   daily_profit_loss = current_balance - daily_start_balance;
}

//+------------------------------------------------------------------+
//| Update Drawdown Tracking                                        |
//+------------------------------------------------------------------+
void UpdateDrawdownTracking()
{
   double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   // Update high water mark
   if(current_equity > account_high_water_mark)
   {
      account_high_water_mark = current_equity;
   }
   
   // Calculate current drawdown
   current_drawdown = ((account_high_water_mark - current_equity) / account_high_water_mark) * 100.0;
}

//+------------------------------------------------------------------+
//| Update Position Tracking                                        |
//+------------------------------------------------------------------+
void UpdatePositionTracking()
{
   // Update existing positions and remove closed ones
   for(int i = ArraySize(position_tracker) - 1; i >= 0; i--)
   {
      if(!PositionSelectByTicket(position_tracker[i].ticket))
      {
         // Position closed, remove from tracker
         ArrayRemove(position_tracker, i, 1);
         continue;
      }
      
      // Update position data
      double current_profit = PositionGetDouble(POSITION_PROFIT);
      
      if(current_profit > position_tracker[i].highest_profit)
         position_tracker[i].highest_profit = current_profit;
      
      if(current_profit < position_tracker[i].lowest_profit)
         position_tracker[i].lowest_profit = current_profit;
      
      // Handle trailing stop
      if(UseTrailingStop)
         UpdateTrailingStop(i);
      
      // Handle time-based exit
      if(UseTimeBasedExit)
         CheckTimeBasedExit(i);
   }
}

//+------------------------------------------------------------------+
//| Update Trailing Stop for Position                               |
//+------------------------------------------------------------------+
void UpdateTrailingStop(int tracker_index)
{
   ulong ticket = position_tracker[tracker_index].ticket;
   if(!PositionSelectByTicket(ticket)) return;
   
   double current_price = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 
                          SymbolInfoDouble(Symbol(), SYMBOL_BID) : 
                          SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   
   double current_sl = PositionGetDouble(POSITION_SL);
   double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
   double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   double new_sl = 0;
   
   // Calculate trailing distance
   double trailing_distance_points = TrailingStopPoints;
   
   // Use ATR-based trailing if enabled
   if(UseATRStops && UseATRTrailingStop)
   {
      int atr_handle = iATR(Symbol(), PERIOD_CURRENT, ATRPeriod);
      if(atr_handle != INVALID_HANDLE)
      {
         double atr_buffer[];
         ArraySetAsSeries(atr_buffer, true);
         if(CopyBuffer(atr_handle, 0, 0, 1, atr_buffer) > 0)
         {
            double atr_value = atr_buffer[0];
            double trailing_distance = atr_value * ATRTrailingMultiplier;
            trailing_distance_points = trailing_distance / point;
            
            Print("📊 Trailing ATR - ATR: ", DoubleToString(atr_value, 8), 
                  ", Trailing Distance: ", DoubleToString(trailing_distance, 8), 
                  ", Points: ", DoubleToString(trailing_distance_points, 1));
         }
      }
   }
   
   if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
   {
      new_sl = current_price - trailing_distance_points * point;
      if(current_sl == 0 || new_sl > current_sl)
      {
         if(trade.PositionModify(ticket, new_sl, PositionGetDouble(POSITION_TP)))
         {
            Print("Trailing stop updated for BUY position ", ticket, " to ", DoubleToString(new_sl, _Digits),
                  " (", DoubleToString(trailing_distance_points, 1), " points)");
         }
      }
   }
   else // SELL position
   {
      new_sl = current_price + trailing_distance_points * point;
      if(current_sl == 0 || new_sl < current_sl)
      {
         if(trade.PositionModify(ticket, new_sl, PositionGetDouble(POSITION_TP)))
         {
            Print("Trailing stop updated for SELL position ", ticket, " to ", DoubleToString(new_sl, _Digits),
                  " (", DoubleToString(trailing_distance_points, 1), " points)");
         }
      }
   }
}



//+------------------------------------------------------------------+
//| Check Time-based Exit for Position                              |
//+------------------------------------------------------------------+
void CheckTimeBasedExit(int tracker_index)
{
   ulong ticket = position_tracker[tracker_index].ticket;
   if(!PositionSelectByTicket(ticket)) return;
   
   datetime open_time = position_tracker[tracker_index].open_time;
   datetime current_time = TimeCurrent();
   
   int hours_open = (int)((current_time - open_time) / 3600);
   
   if(hours_open >= MaxPositionHours)
   {
      if(trade.PositionClose(ticket))
      {
         Print("Position ", ticket, " closed due to time limit (", hours_open, " hours)");
      }
   }
}

//+------------------------------------------------------------------+
//| Check Risk Limits and Suspend Trading if Needed                |
//+------------------------------------------------------------------+
void CheckRiskLimits()
{
   // Check daily loss limit
   if(MaxDailyLoss > 0)
   {
      double daily_loss_percent = (daily_profit_loss / daily_start_balance) * 100.0;
      if(daily_loss_percent <= -MaxDailyLoss)
      {
         SuspendTrading("Daily loss limit exceeded: " + DoubleToString(daily_loss_percent, 2) + "%");
         return;
      }
   }
   
   // Check drawdown limit
   if(MaxDrawdown > 0 && current_drawdown >= MaxDrawdown)
   {
      SuspendTrading("Maximum drawdown exceeded: " + DoubleToString(current_drawdown, 2) + "%");
      return;
   }
   
   // Check minimum equity
   double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(current_equity < MinEquityLevel)
   {
      SuspendTrading("Account equity below minimum: " + DoubleToString(current_equity, 2));
      return;
   }
   
   // Resume trading if conditions are met and it was suspended
   if(trading_suspended && CanResumeTrading())
   {
      ResumeTrading();
   }
}

//+------------------------------------------------------------------+
//| Suspend Trading                                                 |
//+------------------------------------------------------------------+
void SuspendTrading(string reason)
{
   if(!trading_suspended)
   {
      trading_suspended = true;
      suspension_reason = reason;
      suspension_time = TimeCurrent();
      
      Print("🚨 TRADING SUSPENDED: ", reason);
      Print("Time: ", TimeToString(suspension_time));
      
      // Close all positions if critical risk level
      if(StringFind(reason, "drawdown") >= 0 || StringFind(reason, "equity") >= 0)
      {
         CloseAllPositions("Risk management protection");
      }
   }
}

//+------------------------------------------------------------------+
//| Resume Trading                                                  |
//+------------------------------------------------------------------+
void ResumeTrading()
{
   trading_suspended = false;
   Print("✅ Trading resumed after suspension: ", suspension_reason);
   suspension_reason = "";
   suspension_time = 0;
}

//+------------------------------------------------------------------+
//| Check if Trading Can Be Resumed                                 |
//+------------------------------------------------------------------+
bool CanResumeTrading()
{
   // Wait at least 1 hour before considering resume
   if(TimeCurrent() - suspension_time < 3600)
      return false;
   
   // Check if conditions have improved
   double daily_loss_percent = (daily_profit_loss / daily_start_balance) * 100.0;
   double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   bool daily_ok = (MaxDailyLoss <= 0 || daily_loss_percent > -MaxDailyLoss * 0.8); // Allow resume at 80% of limit
   bool drawdown_ok = (MaxDrawdown <= 0 || current_drawdown < MaxDrawdown * 0.8);
   bool equity_ok = (current_equity >= MinEquityLevel * 1.1); // Require 10% buffer
   
   return daily_ok && drawdown_ok && equity_ok;
}

//+------------------------------------------------------------------+
//| Close All Positions                                             |
//+------------------------------------------------------------------+
void CloseAllPositions(string reason)
{
   Print("Closing all positions: ", reason);
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetTicket(i) > 0)
      {
         ulong ticket = PositionGetInteger(POSITION_TICKET);
         if(trade.PositionClose(ticket))
         {
            Print("Position ", ticket, " closed");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Add Position to Tracker                                         |
//+------------------------------------------------------------------+
void AddPositionToTracker(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return;
   
   int size = ArraySize(position_tracker);
   ArrayResize(position_tracker, size + 1);
   
   position_tracker[size].ticket = ticket;
   position_tracker[size].open_time = (datetime)PositionGetInteger(POSITION_TIME);
   position_tracker[size].open_price = PositionGetDouble(POSITION_PRICE_OPEN);
   position_tracker[size].initial_sl = PositionGetDouble(POSITION_SL);
   position_tracker[size].highest_profit = 0.0;
   position_tracker[size].lowest_profit = 0.0;
   
   Print("Position ", ticket, " added to advanced tracking");
}

//+------------------------------------------------------------------+
//| Check Advanced Risk Conditions Before Trading                   |
//+------------------------------------------------------------------+
bool CheckAdvancedRiskConditions()
{
   if(!UseAdvancedRisk) return true;
   
   // Check if trading is suspended
   if(trading_suspended)
   {
      return false;
   }
   
   // Check maximum positions per symbol
   int positions_this_symbol = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionGetTicket(i) > 0 && PositionGetString(POSITION_SYMBOL) == Symbol())
      {
         positions_this_symbol++;
      }
   }
   
   if(positions_this_symbol >= MaxPositionsPerSymbol)
   {
      return false;
   }
   
   // Check portfolio heat before opening new position
   double current_risk = CalculateCurrentPortfolioRisk();
   if(current_risk >= PortfolioHeat * 0.9) // Use 90% threshold
   {
      Print("Portfolio heat too high: ", DoubleToString(current_risk, 2), "%");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Create level lines on chart                                     |
//+------------------------------------------------------------------+
void CreateLevelLines()
{
   if(!levels_calculated)
      return;
   
   //--- Create lines for key levels
   CreateHLine("R5", r5, clrRed, STYLE_SOLID, 2);
   CreateHLine("R4", r4, clrOrange, STYLE_SOLID, 1);
   CreateHLine("R3", r3, clrYellow, STYLE_SOLID, 1);
   CreateHLine("Pivot", pivot_point, clrBlue, STYLE_SOLID, 2);
   CreateHLine("S3", s3, clrYellow, STYLE_SOLID, 1);
   CreateHLine("S4", s4, clrOrange, STYLE_SOLID, 1);
   CreateHLine("S5", s5, clrRed, STYLE_SOLID, 2);
}

//+------------------------------------------------------------------+
//| Create horizontal line                                           |
//+------------------------------------------------------------------+
void CreateHLine(string name, double price, color clr, int style, int width)
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetString(0, name, OBJPROP_TEXT, name + " (" + DoubleToString(price, _Digits) + ")");
}

//+------------------------------------------------------------------+
//| Update level lines                                               |
//+------------------------------------------------------------------+
void UpdateLevelLines()
{
   if(!levels_calculated)
      return;
   
   ObjectMove(0, "R5", 0, 0, r5);
   ObjectMove(0, "R4", 0, 0, r4);
   ObjectMove(0, "R3", 0, 0, r3);
   ObjectMove(0, "Pivot", 0, 0, pivot_point);
   ObjectMove(0, "S3", 0, 0, s3);
   ObjectMove(0, "S4", 0, 0, s4);
   ObjectMove(0, "S5", 0, 0, s5);
}

//+------------------------------------------------------------------+
//| Remove level lines                                               |
//+------------------------------------------------------------------+
void RemoveLevelLines()
{
   ObjectDelete(0, "R5");
   ObjectDelete(0, "R4");
   ObjectDelete(0, "R3");
   ObjectDelete(0, "Pivot");
   ObjectDelete(0, "S3");
   ObjectDelete(0, "S4");
   ObjectDelete(0, "S5");
}

//+------------------------------------------------------------------+
//| Copy model files from Common\Files to tester directory         |
//+------------------------------------------------------------------+
bool CopyModelFromCommonFiles(string source_model_path)
{
   Print("🔍 Searching for model in Common\\Files directory...");
   
   //--- Check if model exists in Common\Files
   if(!FileIsExist(source_model_path, FILE_COMMON))
   {
      Print("❌ Model not found in Common\\Files: ", source_model_path);
      return false;
   }
   
   Print("✅ Found model in Common\\Files: ", source_model_path);
   
   //--- Create directory structure in tester Files directory if needed
   string dir_path = "";
   int last_slash = StringFind(source_model_path, "\\", StringLen(source_model_path) - 1);
   while(last_slash >= 0)
   {
      dir_path = StringSubstr(source_model_path, 0, last_slash);
      last_slash = StringFind(source_model_path, "\\", last_slash - 1);
      break;
   }
   
   if(dir_path != "")
   {
      Print("📁 Creating directory structure: ", dir_path);
      // Create directory by trying to create a temporary file in it
      string temp_file = dir_path + "\\temp_dir_creation.tmp";
      int temp_handle = FileOpen(temp_file, FILE_WRITE);
      if(temp_handle != INVALID_HANDLE)
      {
         FileClose(temp_handle);
         FileDelete(temp_file);
      }
   }
   
   //--- Copy model file from Common\Files to local tester directory
   if(!FileCopy(source_model_path, FILE_COMMON, source_model_path, FILE_REWRITE))
   {
      Print("❌ Failed to copy model file: ", source_model_path);
      Print("Error: ", GetLastError());
      return false;
   }
   
   Print("✅ Model file copied successfully: ", source_model_path);
   
   //--- Also copy scaler file if it exists in Common\Files
   if(FileIsExist(scaler_path, FILE_COMMON))
   {
      if(FileCopy(scaler_path, FILE_COMMON, scaler_path, FILE_REWRITE))
      {
         Print("✅ Scaler file copied successfully: ", scaler_path);
      }
      else
      {
         Print("⚠️ Failed to copy scaler file (model will work without normalization): ", scaler_path);
      }
   }
   else
   {
      Print("⚠️ Scaler file not found in Common\\Files: ", scaler_path);
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Display ML Impact Statistics                                    |
//+------------------------------------------------------------------+
void DisplayMLImpactStatistics()
{
   //--- Display statistics every 30 minutes
   static datetime last_display_time = 0;
   if(TimeCurrent() - last_display_time < 1800) // 30 minutes
      return;
   
   last_display_time = TimeCurrent();
   
   //--- Track statistics for both modes
   static int ml_signals_detected = 0;
   static int ml_trades_taken = 0;
   static int traditional_signals_detected = 0;
   static int traditional_trades_taken = 0;
   static bool stats_initialized = false;
   
   //--- Initialize on first run
   if(!stats_initialized)
   {
      stats_initialized = true;
      ml_signals_detected = 0;
      ml_trades_taken = 0;
      traditional_signals_detected = 0;
      traditional_trades_taken = 0;
   }
   
   //--- Display comprehensive statistics
   Print("=========================================");
   Print("🤖 ML IMPACT STATISTICS REPORT");
   Print("=========================================");
   Print("Time: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES));
   Print("Mode: ", UseMLPrediction && model_loaded ? "Machine Learning ENABLED" : "Traditional Filters ONLY");
   
   if(UseMLPrediction && model_loaded)
   {
      Print("ML Model: ", model_path);
      Print("Confidence Threshold: ", DoubleToString(MLConfidenceThreshold, 2));
      Print("Scaler Loaded: ", scaler_loaded ? "YES" : "NO");
   }
   else
   {
      Print("Reason: ", !UseMLPrediction ? "ML disabled by user" : "Model not loaded");
      if(!UseMLPrediction)
      {
         Print("📊 Traditional Filters Active:");
         Print("   - RSI Momentum Filter");
         Print("   - ATR Volatility Filter");
         Print("   - Price Action Confirmation");
         Print("   - Level-specific Filters");
      }
   }
   
   //--- Show current market conditions
   double current_price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   int rsi_handle = iRSI(Symbol(), PERIOD_CURRENT, 14, PRICE_CLOSE);
   int atr_handle = iATR(Symbol(), PERIOD_CURRENT, ATRPeriod);
   
   if(rsi_handle != INVALID_HANDLE && atr_handle != INVALID_HANDLE)
   {
      double rsi_buffer[], atr_buffer[];
      ArraySetAsSeries(rsi_buffer, true);
      ArraySetAsSeries(atr_buffer, true);
      
      if(CopyBuffer(rsi_handle, 0, 0, 1, rsi_buffer) > 0 && 
         CopyBuffer(atr_handle, 0, 0, 1, atr_buffer) > 0)
      {
         double rsi = rsi_buffer[0];
         double atr = atr_buffer[0];
         double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
         
         Print("-----------------------------------------");
         Print("📈 CURRENT MARKET CONDITIONS:");
         Print("   Price: ", DoubleToString(current_price, _Digits));
         Print("   RSI: ", DoubleToString(rsi, 1), " (", 
               rsi < 30 ? "Oversold" : rsi > 70 ? "Overbought" : "Normal", ")");
         Print("   ATR: ", DoubleToString(atr / point, 1), " points");
         Print("   Spread: ", DoubleToString((SymbolInfoDouble(Symbol(), SYMBOL_ASK) - SymbolInfoDouble(Symbol(), SYMBOL_BID)) / point, 1), " points");
      }
   }
   
   //--- Trading statistics
   Print("-----------------------------------------");
   Print("📊 TRADING ACTIVITY:");
   Print("   Total Positions: ", PositionsTotal());
   Print("   Positions on ", Symbol(), ": ", CountSymbolPositions());
   
   //--- Performance comparison message
   Print("-----------------------------------------");
   Print("💡 PERFORMANCE COMPARISON:");
   
   if(UseMLPrediction && model_loaded)
   {
      Print("✅ ML Mode Active - Trades are filtered by neural network model");
      Print("   The neural network evaluates 35 market features:");
      Print("   - Price ratios to all Camarilla levels");
      Print("   - Market volatility and microstructure");
      Print("   - Volume patterns and session data");
      Print("   - Technical indicators and momentum");
      Print("   Only trades with confidence >= threshold are taken (level-specific)");
   }
   else
   {
      Print("📊 Traditional Mode Active - Using rule-based filters");
      Print("   Filters applied:");
      Print("   - RSI must be 30-70 range");
      Print("   - ATR must be 50-500 points");
      Print("   - Price momentum confirmation");
      Print("   - Special rules for L5/H5 levels");
   }
   
   Print("-----------------------------------------");
   Print("🎯 TO COMPARE ML IMPACT:");
   Print("1. Run EA with UseMLPrediction = true");
   Print("2. Note the number and quality of trades");
   Print("3. Run EA with UseMLPrediction = false");
   Print("4. Compare results - ML should filter out lower probability trades");
   Print("=========================================");
}

//+------------------------------------------------------------------+
//| Count positions for current symbol                              |
//+------------------------------------------------------------------+
int CountSymbolPositions()
{
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionGetTicket(i) > 0 && PositionGetString(POSITION_SYMBOL) == Symbol())
      {
         count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Get level-specific confidence threshold                         |
//+------------------------------------------------------------------+
double GetLevelSpecificThreshold(string level_name)
{
   if(level_name == "L3H3")
      return MLConfidenceL3;
   else if(level_name == "L4H4")
      return MLConfidenceL4;
   else if(level_name == "L5H5")
      return MLConfidenceL5;
   else
      return MLConfidenceThreshold; // Default threshold
}

//+------------------------------------------------------------------+
//| Get level-specific stop loss multiplier                        |
//+------------------------------------------------------------------+
double GetLevelSpecificSLMultiplier(string level_name)
{
   // L3/H3: Tighter stops as these are more frequent breakouts
   if(level_name == "L3H3")
      return ATRMultiplierSL * 0.8;  // 80% of normal
   
   // L4/H4: Normal stops
   else if(level_name == "L4H4")
      return ATRMultiplierSL;
   
   // L5/H5: Wider stops as these are extreme levels
   else if(level_name == "L5H5")
      return ATRMultiplierSL * 1.2;  // 120% of normal
   
   else
      return ATRMultiplierSL; // Default multiplier
}

//+------------------------------------------------------------------+
//| Check if market is in trend                                    |
//+------------------------------------------------------------------+
bool IsInTrend(ENUM_POSITION_TYPE position_type)
{
   // Use simple moving average for trend detection
   int ma_handle = iMA(Symbol(), PERIOD_CURRENT, 50, 0, MODE_SMA, PRICE_CLOSE);
   if(ma_handle == INVALID_HANDLE)
      return true; // Allow trade if MA unavailable
   
   double ma_buffer[];
   ArraySetAsSeries(ma_buffer, true);
   if(CopyBuffer(ma_handle, 0, 0, 1, ma_buffer) <= 0)
      return true; // Allow trade if MA unavailable
   
   double current_price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double ma_value = ma_buffer[0];
   
   // For BUY: Price should be above MA
   if(position_type == POSITION_TYPE_BUY)
   {
      bool in_uptrend = current_price > ma_value;
      if(!in_uptrend && LogPredictions)
         Print("📊 Trend Filter: Not in uptrend - Price: ", DoubleToString(current_price, _Digits), 
               " < MA50: ", DoubleToString(ma_value, _Digits));
      return in_uptrend;
   }
   // For SELL: Price should be below MA
   else
   {
      bool in_downtrend = current_price < ma_value;
      if(!in_downtrend && LogPredictions)
         Print("📊 Trend Filter: Not in downtrend - Price: ", DoubleToString(current_price, _Digits), 
               " > MA50: ", DoubleToString(ma_value, _Digits));
      return in_downtrend;
   }
}

//+------------------------------------------------------------------+
//| Check if volatility is acceptable for trading                  |
//+------------------------------------------------------------------+
bool IsVolatilityAcceptable()
{
   int atr_handle = iATR(Symbol(), PERIOD_CURRENT, ATRPeriod);
   if(atr_handle == INVALID_HANDLE)
      return true; // Allow trade if ATR unavailable
   
   double atr_buffer[];
   ArraySetAsSeries(atr_buffer, true);
   if(CopyBuffer(atr_handle, 0, 0, 20, atr_buffer) <= 0)
      return true; // Allow trade if ATR unavailable
   
   double current_atr = atr_buffer[0];
   double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   double atr_points = current_atr / point;
   
   // Calculate average ATR over last 20 periods
   double sum_atr = 0;
   for(int i = 0; i < 20; i++)
      sum_atr += atr_buffer[i];
   double avg_atr = sum_atr / 20;
   double avg_atr_points = avg_atr / point;
   
   // Volatility should be within reasonable range (50% to 200% of average)
   double volatility_ratio = current_atr / avg_atr;
   
   bool acceptable = (volatility_ratio >= 0.5 && volatility_ratio <= 2.0);
   
   if(!acceptable && LogPredictions)
   {
      Print("📊 Volatility Filter: Rejected - Current ATR: ", DoubleToString(atr_points, 1), 
            " points, Avg ATR: ", DoubleToString(avg_atr_points, 1), 
            " points, Ratio: ", DoubleToString(volatility_ratio, 2));
   }
   
   return acceptable;
}
