//EAsource     =>  ...\MT4\MQL4\Experts
//@kingkingisme  <= TG

#property  copyright "战凌云"
#property description "QQ群666666121"
#property version   "1.00"

// ============================================================================
// Gold Trade Pro - MT5 build (MQL4 -> MQL5 compatibility-layer port)
// ----------------------------------------------------------------------------
// Source   : Gold Trade Pro.mq4 (5779 lines, decompiled/reconstructed)
// Method   : keep the original MQL4 logic untouched; run it on MQL5 through
//            <MQL4Compat.mqh>. Automatic transforms applied by port_gtp.ps1:
//              . CJK identifier prefixes -> ASCII (MQL5 allows ASCII only)
//              . extern -> input; drop #property strict; fix #property version
//              . int init()   -> int OnInit()
//              . int deinit() -> void OnDeinit(const int reason)
//            OnTick() already used that name in the source, unchanged.
// NOTE     : this EA opens multiple concurrent positions -> HEDGING account.
// DISCLAIM  : source origin unknown (shared group resource, batch-renamed
//            decompiler output). Research only. Do not run on live funds.
// ============================================================================

#include <MQL4Compat.mqh>



  enum e_SlippageControlMode      {SCT_2 = 2,SCT_1 = 1  };
  enum e_VirtualStopMode      {VSL_ADV = 3,VSL_BASIC = 2,VSL_OFF = 1  };
  enum Select_Entry_Strategy      {Strategy_TWO = 2,Strategy_ONE = 1  };
  enum e_TimeFrame_St_ONE      {ST1_Chart = 0,ST1_Daily = 1440,ST1_H4 = 240,ST1_H1 = 60,ST1_M30 = 30,ST1_M15 = 15,ST1_M5 = 5,ST1_M1 = 1  };
  enum e_TimeFrame_Entry_Timing      {Entry_T_H4 = 240,Entry_T_H1 = 60,Entry_T_M30 = 30,Entry_T_M15 = 15,Entry_T_M5 = 5,Entry_T_M1 = 1,Entry_T_Tick = 0  };
  enum e_UseOfCompound      {Multi_trades = 2,one_trade = 1,no_compound = 0  };
  enum e_MonitorTradesFilter      {MT_PairOfChart = 1,MT_all = 0  };
  enum e_TimeFrame_Exit_Timing      {ET_H1 = 60,ET_M30 = 30,ET_M15 = 15,ET_M5 = 5,ET_M1 = 1,ET_Tick = 0  };
  enum e_Exit_HL_trailingSL_timeframe      {HLT_D1 = 1440,HLT_H4 = 240,HLT_H1 = 60,HLT_M30 = 30,HLT_M15 = 15,HLT_M5 = 5,HLT_M1 = 1,HLT_Chart = 0  };
  enum ST1_e_MagicTrail_Mode      {ST1_MT_M_B = 2,ST1_MT_M_F = 1,ST1_MT_M_O = 0  };
  enum e_Risk      {RPT = 999,//Manual RiskPerTrade
                   Lots_Per_Balance = 9999,//use LotsizeStep
                   Manual_Lotsize = 0//use Startlots
                     };
  enum Performance_options      {RealProfit = 1,NormalizedProfit = 2  };
  enum RankingOptions      {ranking_pertrade = 2,ranking_profit = 1  };
  enum Reduction_choices      {Red_90 = 90,Red_80 = 80,Red_70 = 70,Red_60 = 60,Red_50 = 50,Red_40 = 40,Red_30 = 30,Red_20 = 20,Red_10 = 10  };
  enum e_factortype      {factor_type_3 = 3,factor_type_2 = 2,factor_type_1 = 1  };
  enum e_TimeSource      {TZ_Broker = 2,TZ_PC = 1,TZ_GMT = 0  };


//------------------
input bool ShowInfoPanel=true  ;   
input double InfoPanelSizeAdjust=1  ;    //Adjustment for Infopanel size
input bool UpdateInfoTesting=false ;    //update infopanel during testing
input string spreadfilter="------------------------------ Settings ------------------------------"  ;   //- - -
input bool RunStrategyA=true  ;    //run strategy 1
input bool RunStrategyC=true  ;    //run strategy 2
input bool RunStrategyD=true  ;    //run strategy 3
input bool RunStrategyE=true  ;    //run strategy 4
input bool RunStrategyF=true  ;    //run strategy 5
input bool RunStrategyG=true  ;    //run strategy 6
input bool RunStrategyH=true  ;    //run strategy 7
input double MaxSpread=500  ;    //Maximum allowed spread
input bool setSL_TP_After_Entry=false ;   
input bool Virtual_expiration=true  ;    //Use Virtual Expiration
input int   ST1_MagicNumber=1000  ;    //BaseMagicnumber
input string ST1_Comment="Gold Trade Pro"  ;   //Comment for trades
input string LotSizeSettings="----------------------- LotSize Settings -----------------------"  ;   //- - -
input  e_Risk  Risk=0  ;    //Lotsize Calculation method
input double StartLots_Input=0.01  ;   // 原 StartLots：MQL5 中 input 不可修改，改由全局副本 StartLots 承接
double StartLots=0.01;                 // 运行期可修改（对应原 MQL4 代码里的 StartLots 赋值）   
input int   LotPerBalance_step=600  ;    //LotsizeStep
input double Manual_RiskPerTrade=2  ;    //Max Risk Per Trade
input bool UseEquity=false ;    //Use Equity Instead of Balance
input bool OnlyUp=true  ;   
  double    L_1_do_0 = 0.0;
  bool      L_2_bo_8 = false;
  int       L_3_in_C = 3;
  int       L_4_in_10 = 2;
  bool      L_5_bo_14 = false;
  bool      L_6_bo_15 = false;
  int       L_7_in_18 = 0;
  string    L_8_st_20 = "------------------------------ trading filters ------------------------------";
  bool      L_9_bo_2C = false;
  string    L_10_st_30 = "EURUSD;GBPUSD;USDJPY;AUDJPY;AUDUSD;EURAUD;EURCAD;EURGBP;EURJPY;GBPJPY;USDCAD;USDCHF;";
  bool      L_11_bo_3C = false;
  bool      L_12_bo_3D = true;
  int       L_13_in_40 = 2;
  double    L_14_do_48 = 0.0;
  double    L_15_do_50 = 100.0;
  int       L_16_in_58 = 1;
  double    L_17_do_60 = 4.0;
  double    L_18_do_68 = 1.0;
  double    L_19_do_70 = 3.0;
  bool      L_20_bo_78 = true;
  string    L_21_st_80 = "------------------------------ time filters ------------------------------";
  bool      L_22_bo_8C = false;
  int       L_23_in_90 = 25;
  bool      L_24_bo_94 = false;
  bool      L_25_bo_95 = false;
  int       L_26_in_98 = 14;
  int       L_27_in_9C = 17;
  string    L_28_st_A0 = "------------------------------ other filters ------------------------------";
  bool      L_29_bo_AC = false;
  int       L_30_in_B0 = 1;
  double    L_31_do_B8 = 0.0;
  int       L_32_in_C0 = 99;
  int       L_33_in_C4 = 5;
  bool      L_34_bo_C8 = false;
  int       L_35_in_CC = 5;
  bool      L_36_bo_D0 = true;
  int       L_37_in_D4 = 1;
  string    L_38_st_D8 = "------------------------------ Trade Entry management ------------------------------";
  int       L_39_in_E4 = 0;
  int       L_40_in_E8 = 60;
  int       L_41_in_EC = 10;
  int       L_42_in_F0 = 3;
  bool      L_43_bo_F4 = false;
  bool      L_44_bo_F5 = false;
  int       L_45_in_F8 = 120;
  int       L_46_in_FC = 0;
  int       L_47_in_100 = 0;
  double    L_48_do_108 = 30.0;
  double    L_49_do_110 = 0.0;
  int       L_50_in_118 = 0;
  int       L_51_in_11C = 1077477376;
  double    L_52_do_120 = 0.5;
  double    L_53_do_128 = 0.0;
  double    L_54_do_130 = 0.0;
  int       L_55_in_138 = 1;
  double    L_56_do_140 = 1.0;
  int       L_57_in_148 = 24;
  int       L_58_in_150 = 0;
  int       L_59_in_154 = 1074266112;
  int       L_60_in_158 = 0;
  int       L_61_in_15C = 100;
  int       L_62_in_160 = 0;
  string    L_63_st_168 = "------------------------------ Strategy 2 - Manual Trade settings ------------------------------";
  int       L_64_in_174 = 1;
  int       L_65_in_178 = 0;
  string    L_66_st_180 = "";
  string    L_67_st_190 = "------------------------------ Trade Exit management ------------------------------";
  int       L_68_in_19C = 0;
  double    L_69_do_1A0 = 20.0;
  double    L_70_do_1A8 = 100.0;
  string    L_71_st_1B0 = "------------------------------ Trailing SL settings ------------------------------";
  double    L_72_do_1C0 = 10.0;
  double    L_73_do_1C8 = 10.0;
  double    L_74_do_1D0 = 100.0;
  double    L_75_do_1D8 = 0.1;
  double    L_76_do_1E0 = 0.0;
  string    L_77_st_1E8 = "------------------------------ Break-even SL management ------------------------------";
  double    L_78_do_1F8 = 0.0;
  double    L_79_do_200 = 0.0;
  string    L_80_st_208 = "------------------------------ HIGH/LOW Trailing SL settings ------------------------------";
  bool      L_81_bo_214 = false;
  int       L_82_in_218 = 0;
  int       L_83_in_21C = 0;
  int       L_84_in_220 = 0;
  int       L_85_in_224 = 0;
  int       L_86_in_228 = 0;
  double    L_87_do_230 = 2.0;
  string    L_88_st_238 = "------------------------------ recovery Trailing SL based on time ------------------------------";
  double    L_89_do_248 = 0.0;
  double    L_90_do_250 = 0.0;
  string    L_91_st_258 = "------------------------------ MagicTrail SL settings ------------------------------";
  int       L_92_in_264 = 0;
  double    L_93_do_268 = 0.1;
  int       L_94_in_270 = 1;
  double    L_95_do_278 = 0.1;
  double    L_96_do_280 = 1.0;
  int       L_97_in_288 = 0;
  double    L_98_do_290 = 0.0;
  bool      L_99_bo_298 = false;
  bool      L_100_bo_299 = false;
  double    L_101_do_2A0 = 5.0;
  double    L_102_do_2A8 = 99.0;
  int       L_103_in_2B0 = 99999;
  double    L_104_do_2B8 = 10.0;
  string    L_105_st_2C0 = "==== Performance numbers overview ====";
  bool      L_106_bo_2CC = true;
  int       L_107_in_2D0 = 1;
  int       L_108_in_2D4 = 1;
  int       L_109_in_2D8 = 90;
  int       L_110_in_2DC = 30;
  int       L_111_in_2E0 = 10;
  int       L_112_in_2E4 = 50;
  bool      L_113_bo_2E8 = true;
  string    L_114_st_2F0 = "------------------------------ zone_recovery_settings ------------------------------";
  bool      L_115_bo_2FC = false;
  double    L_116_do_300 = 50.0;
  double    L_117_do_308 = 10.0;
  double    L_118_do_310 = 5.0;
  double    L_119_do_318 = 0.0;
  int       L_120_in_320 = 1;
  double    L_121_do_328 = 2.0;
  int       L_122_in_330 = 999;
  int       L_123_in_338 = 0;
  int       L_124_in_33C = 1079574528;
  int       L_125_in_340 = 900010;
  int       L_126_in_344 = 900011;
  string    L_127_st_348 = "------------------------- Trading hours ST1 -------------------------";
  bool      L_128_bo_354 = false;
  int       L_129_in_358 = 2;
  bool      L_130_bo_35C = false;
  int       L_131_in_360 = 0;
  int       L_132_in_364 = 24;
  int       L_133_in_368 = 0;
  int       L_134_in_36C = 24;
  int       L_135_in_370 = 0;
  int       L_136_in_374 = 24;
  int       L_137_in_378 = 0;
  int       L_138_in_37C = 24;
  int       L_139_in_380 = 0;
  int       L_140_in_384 = 24;
  int       L_141_in_388 = 0;
  int       L_142_in_38C = 24;
  string    L_143_st_390 = "------------------------- use for backtesting only! -------------------------";
  int       L_144_in_39C = 0;
  double    L_145_do_3A0 = 0.0;
  double    L_146_do_3A8 = 0.0;
  int       L_147_in_3B0 = 0;
  double    L_148_do_3B8 = 0.0;
  int       L_149_in_3C0 = 0;
  int       L_150_in_3C4 = 0;
  bool      L_151_bo_3C8 = false;
  bool      L_152_bo_3C9 = false;
  double    L_153_do_400_si20si2[20][2];
  double    L_154_do_574_si100si3[100][3];
  double    L_155_do_F08_si100si2[100][2];
  int       L_156_in_1548 = 20;
  int       L_157_in_154C = 100;
  int       L_158_in_1550 = 0;
  int       L_159_in_1554 = 0;
  int       L_160_in_1558 = 0;
  int       L_161_in_155C = 0;
  int       L_162_in_1560 = 0;
  int       L_163_in_1564 = 0;
  int       L_164_in_1568 = 0;
  int       L_165_in_156C = 0;
  int       L_166_in_1570 = 0;
  int       L_167_in_1574 = 0;
  int       L_168_in_1578 = 0;
  int       L_169_in_157C = 0;
  bool      L_170_bo_1580 = false;
  int       L_171_in_1584 = 10;
  int       L_172_in_1588 = 0;
  int       L_173_in_158C = 0;
  int       L_174_in_1590 = 0;
  int       L_175_in_1594 = 0;
  int       L_176_in_1598 = 0;
  int       L_177_in_159C = 0;
  int       L_178_in_15A0 = 0;
  int       L_179_in_15A4 = 0;
  bool      L_180_bo_15A8 = false;
  int       L_181_in_15AC = 1;
  datetime  L_182_da_15E4_si99[99];
  int       L_183_in_1900 = 0;
  int       L_184_in_1904 = 0;
  int       L_185_in_1908 = 370;
  bool      L_186_bo_190C = true;
  bool      L_187_bo_190D = false;
  int       L_188_in_1910 = 0;
  double    L_189_do_1918 = 4.0;
  int       L_190_in_1920 = 0;
  int       L_191_in_1924 = 0;
  double    L_192_do_195C_si99[99];
  int       L_193_in_1C78 = 0;
  int       L_194_in_1C7C = 0;
  int       L_195_in_1C80 = 0;
  int       L_196_in_1C84 = 0;
  int       L_197_in_1C88 = 0;
  int       L_198_in_1C8C = 0;
  int       L_199_in_1C90 = 0;
  int       L_200_in_1C94 = 0;
  double    L_201_do_1C98 = 0.0;
  int       L_202_in_1CA0 = 0;
  bool      L_203_bo_1CA4 = false;
  int       L_204_in_1CA8 = 0;
  int       L_205_in_1CAC = 0;
  int       L_206_in_1CB0 = 0;
  int       L_207_in_1CB4 = 0;
  int       L_208_in_1CB8 = 0;
  int       L_209_in_1CC0 = 0;
  int       L_210_in_1CC4 = 0;
  int       L_211_in_1CC8 = 0;
  int       L_212_in_1CCC = 0;
  int       L_213_in_1CD0 = 0;
  int       L_214_in_1CD4 = 0;
  bool      L_215_bo_1CD8 = false;
  bool      L_216_bo_1CD9 = false;
  bool      L_217_bo_1CDA = false;
  double    L_218_do_1CE0 = 0.0;
  double    L_219_do_1CE8 = 0.0;
  int       L_220_in_1CF0 = 0;
  int       L_221_in_1CF4 = 0;
  int       L_222_in_1CF8 = 0;
  int       L_223_in_1CFC = 0;
  int       L_224_in_1D00 = 0;
  int       L_225_in_1D04 = 0;
  int       L_226_in_1D08 = 0;
  int       L_227_in_1D0C = 0;
  double    L_228_do_1D10 = 0.0;
  int       L_229_in_1D18 = 0;
  int       L_230_in_1D1C = 0;
  int       L_231_in_1D20 = 0;
  int       L_232_in_1D24 = 0;
  int       L_233_in_1D28 = 0;
  double    L_234_do_1D30 = 0.0;
  string    L_235_st_1D38;
  string    L_236_st_1D48;
  string    L_237_st_1D58;
  string    L_238_st_1D68;
  bool      L_239_bo_1D74 = false;
  bool      L_240_bo_1D75 = false;
  int       L_241_in_1D78 = 0;
  int       L_242_in_1D7C = 0;
  double    L_243_do_1D80 = 0.0;
  double    L_244_do_1D88 = 0.0;
  double    L_245_do_1D90 = 0.0;
  double    L_246_do_1D98 = 0.0;
  double    L_247_do_1DA0 = 0.0;
  int       L_248_in_1DA8 = 0;
  int       L_249_in_1DAC = 0;
  int       L_250_in_1DB0 = 0;
  double    L_251_do_1DB8 = 0.0;
  double    L_252_do_1DC0 = 0.0;
  double    L_253_do_1DC8 = 0.0;
  double    L_254_do_1DD0 = 0.0;
  double    L_255_do_1DD8 = 0.0;
  double    L_256_do_1DE0 = 0.0;
  int       L_257_in_1DE8 = 0;
  int       L_258_in_1DF0 = 0;
  int       L_259_in_1DF4 = 0;
  int       L_260_in_1DF8 = 0;
  int       L_261_in_1DFC = 0;
  int       L_262_in_1E00 = 0;
  int       L_263_in_1E04 = 0;
  bool      L_264_bo_1E08 = false;
  bool      L_265_bo_1E09 = false;
  bool      L_266_bo_1E0A = false;
  bool      L_267_bo_1E0B = false;
  bool      L_268_bo_1E0C = false;
  bool      L_269_bo_1E0D = false;
  int       L_270_in_1E10 = 0;
  int       L_271_in_1E14 = 0;
  int       L_272_in_1E18 = 0;
  int       L_273_in_1E1C = 0;
  bool      L_274_bo_1E20 = false;
  int       L_275_in_1E28 = 0;
  int       L_276_in_1E2C = 0;
  int       L_277_in_1E30 = 0;
  int       L_278_in_1E34 = 0;
  int       L_279_in_1E38 = 0;
  int       L_280_in_1E3C = 0;
  double    L_281_do_1E74_si10[10];
  double    L_282_do_1EF8_si10[10];
  double    L_283_do_1F7C_si10[10];
  double    L_284_do_2000_si10[10];
  int       L_285_in_2050 = 0;
  int       L_286_in_2054 = 0;
  int       L_287_in_2058 = 0;
  int       L_288_in_205C = 0;
  string    L_289_st_2060;
  int       L_290_in_2070 = 0;
  int       L_291_in_2074 = 0;
  int       L_292_in_2078 = 0;
  int       L_293_in_207C = 0;
  datetime  L_294_da_2080 = 0;
  bool      L_295_bo_2088 = false;
  int       L_296_in_208C = 0;
  bool      L_297_bo_2090 = false;
  int       L_298_in_2094 = 0;
  double    L_299_do_2098 = 0.0;
  int       L_300_in_20A0 = 0;
  int       L_301_in_20A4 = 0;
  double    L_302_do_20A8 = 0.0;
  double    L_303_do_20B0 = 0.0;
  double    L_304_do_20B8 = 0.0;
  bool      L_305_bo_20C0 = false;
  datetime  L_306_da_20C8 = 0;
  datetime  L_307_da_20D0 = 0;
  datetime  L_308_da_20D8 = 0;
  bool      L_309_bo_20E0 = false;
  bool      L_310_bo_20E1 = false;
  double    L_311_do_20E8 = 0.0;
  datetime  L_312_da_20F0 = 0;
  bool      L_313_bo_20F8 = false;
  int       L_314_in_2130_si99[99];
  int       L_315_in_22F0_si99[99];
  double    L_316_do_24B0_si30[30];
  double    L_317_do_25D4_si30[30];
  double    L_318_do_26F8_si30[30];
  double    L_319_do_281C_si30[30];
  int       L_320_in_290C = 1;
  int       L_321_in_2910 = 0;
  int       L_322_in_2914 = 9109504;
  bool      L_323_bo_2918 = false;
  int       L_324_in_2920 = 0;
  int       L_325_in_2924 = 0;
  int       L_326_in_2928 = 5;
  bool      L_327_bo_292C = false;
  string    L_328_st_2930;
  bool      L_329_bo_293C = false;
  string    L_330_st_2940;
  double    L_331_do_2950 = 0.0;
  double    L_332_do_2958 = 0.0;
  int       L_333_in_2994_si99[99];
  int       L_334_in_2B20 = 0;
  double    L_335_do_2B58_si99[99];
  bool      L_336_bo_2EA4_si99[99];
  int       L_337_in_2F3C_si99[99];
  int       L_338_in_30FC_si99[99];
  double    L_339_do_32BC_si99[99];
  double    L_340_do_3608_si99[99];
  string    L_341_st_3954_si99[99]={};
  bool      L_342_bo_3E2C_si99[99];
  double    L_343_do_3EC4_si99[99];
  double    L_344_do_4210_si99[99];
  double    L_345_do_455C_si99[99];
  double    L_346_do_48A8_si99[99];
  double    L_347_do_4BF4_si99[99];
  double    L_348_do_4F40_si99[99];
  bool      L_349_bo_528C_si99[99];
  int       L_350_in_5324_si99[99];
  bool      L_351_bo_54B0 = false;
  int       L_352_in_54B8 = 0;
  int       L_353_in_54BC = 1075052544;
  int       L_354_in_54C0 = 0;
  int       L_355_in_54C4 = 1076101120;
  int       L_356_in_54C8 = 0;
  double    L_357_do_54D0 = 0.0;
  double    L_358_do_54D8 = 0.0;
  int       L_359_in_54E0 = 0;
  int       L_360_in_54E4 = 14599344;
  bool      L_361_bo_54E8 = true;
  int       L_362_in_54F0 = 0;
  int       L_363_in_54F4 = 1076363264;
  int       L_364_in_54F8 = 230;
  int       L_365_in_54FC = 320;
  int       L_366_in_5500 = 500;
  int       L_367_in_5504 = 350;
  int       L_368_in_5508 = 2;
  int       L_369_in_550C = 7;
  int       L_370_in_5510 = 10;
  int       L_371_in_5514 = 30;
  string    L_372_st_554C_si4[4]={};
  double    L_373_do_5580 = 0.45;
  double    L_374_do_5588 = 0.6;
  int       L_375_in_5590 = 0;
  datetime  L_376_da_5598 = 0;
  bool      L_377_bo_55A0 = false;
  int       L_378_in_55A4 = 0;


int OnInit()
 {
  StartLots = StartLots_Input;   // input 不可变，赋值给运行期副本
  int       W_2_in;
  int       W_3_in;
  int       W_4_in;
  int       W_5_in;
  int       W_6_in;
  int       W_7_in;
//----- -----
 string     X_st_1;
 bool       X_bo_2;
 bool       X_bo_3;

 L_376_da_5598 = 0 ;
 L_377_bo_55A0 = true ;
 L_352_in_54B8 = 0 ;
 L_353_in_54BC = 1075052544 ;
 L_354_in_54C0 = 0 ;
 L_355_in_54C4 = 1076101120 ;
 L_62_in_160 = ST1_MagicNumber ;
 L_356_in_54C8 = 300 ;
 L_357_do_54D0 = L_369_in_550C * 25 * L_373_do_5580 * InfoPanelSizeAdjust ;
 L_358_do_54D8 = L_369_in_550C * 3.5 * L_374_do_5588 * InfoPanelSizeAdjust ;
 L_359_in_54E0 = 7 ;
 L_321_in_2910 = 0 ;
 L_330_st_2940 = Symbol() ;
 L_331_do_2950 = SymbolInfoDouble(L_330_st_2940,16) ;
 L_201_do_1C98 = L_331_do_2950 ;
 if ( ( MarketInfo(L_330_st_2940,MODE_DIGITS)==3.0 || MarketInfo(L_330_st_2940,MODE_DIGITS)==5.0 ) )
 {
   L_201_do_1C98 = L_331_do_2950 * 10.0 ;
 }
 L_147_in_3B0 = MarketInfo(L_330_st_2940,MODE_DIGITS) ;
 if ( L_23_in_90 <  0 )
 {
   L_22_bo_8C = false ;
 }
 L_234_do_1D30 = TimeCurrent() ;
 L_1_do_0 = MarketInfo(L_330_st_2940,MODE_ASK) - MarketInfo(L_330_st_2940,MODE_BID) ;
 L_192_do_195C_si99[L_321_in_2910] = NormalizeDouble(MathFloor(StartLots * 100.0) / 100.0,2);
 if ( MarketInfo(L_330_st_2940,MODE_LOTSTEP)==0.1 )
 {
   L_192_do_195C_si99[L_321_in_2910] = NormalizeDouble((MathFloor(StartLots * 10.0)) / 10.0,1);
   if ( L_192_do_195C_si99[L_321_in_2910]<0.1 )
   {
     L_192_do_195C_si99[L_321_in_2910] = 0.1;
   }
 }
 if ( L_192_do_195C_si99[L_321_in_2910]<MarketInfo(L_330_st_2940,MODE_MINLOT) )
 {
   Print("Minimum lotsize for this broker is " + string(MarketInfo(L_330_st_2940,MODE_MINLOT)) + "lots!!"); 
   L_192_do_195C_si99[L_321_in_2910] = MarketInfo(L_330_st_2940,MODE_MINLOT);
 }
 if ( L_192_do_195C_si99[L_321_in_2910]>MarketInfo(L_330_st_2940,MODE_MAXLOT) )
 {
   Print("Maximum lotsize for this broker is " + string(MarketInfo(L_330_st_2940,MODE_MAXLOT)) + "lots!!"); 
   L_192_do_195C_si99[L_321_in_2910] = MarketInfo(L_330_st_2940,MODE_MAXLOT);
 }
 L_298_in_2094 = iBars(_Symbol,_Period) ;
 if ( L_95_do_278 * L_201_do_1C98<L_331_do_2950 )
 {
   L_95_do_278 = L_331_do_2950 / L_201_do_1C98 ;
 }
 L_299_do_2098 = AccountBalance() ;
 L_189_do_1918 = MarketInfo(L_330_st_2940,MODE_STOPLEVEL) * L_331_do_2950 ;
 L_302_do_20A8 = MarketInfo(L_330_st_2940,MODE_FREEZELEVEL) * L_331_do_2950 ;
 L_289_st_2060 = StringSubstr(Symbol(),6,10) ;
 if ( L_289_st_2060 != "" )
 {
   Print("Suffix detected: " + L_289_st_2060); 
 }
 if ( ( StringFind(Symbol(),"XAUUSD",0) >= 0 || StringFind(Symbol(),"xauusd",0) >= 0 || StringFind(Symbol(),"GOLD",0) >= 0 || StringFind(Symbol(),"gold",0) >= 0 || StringFind(Symbol(),"Gold",0) >= 0 ) )
 {
   L_330_st_2940 = Symbol() ;
   L_341_st_3954_si99[L_375_in_5590] = Symbol();
   L_39_in_E4 = 1440 ;
   L_40_in_E8 = 60 ;
   L_41_in_EC = 4 ;
   L_42_in_F0 = 2 ;
   L_45_in_F8 = 160 ;
   L_48_do_108 = 150.0 ;
   L_49_do_110 = 0.0 ;
   L_52_do_120 = -140.0 ;
   L_53_do_128 = -290.0 ;
   L_55_in_138 = 1 ;
   L_56_do_140 = 680.0 ;
   L_57_in_148 = 408 ;
   L_68_in_19C = 1 ;
   L_69_do_1A0 = 1300.0 ;
   L_70_do_1A8 = 1700.0 ;
   L_72_do_1C0 = 800.0 ;
   L_73_do_1C8 = 500.0 ;
   L_74_do_1D0 = 200.0 ;
   L_75_do_1D8 = 0.1 ;
   L_76_do_1E0 = 0.0 ;
   L_328_st_2930=ST1_Comment + "_XAUUSD_A";
   L_62_in_160=ST1_MagicNumber + 1;
   L_321_in_2910 = 0 ;
   L_331_do_2950 = SymbolInfoDouble(L_330_st_2940,16) ;
   L_201_do_1C98 = L_331_do_2950 ;
   if ( ( MarketInfo(L_330_st_2940,MODE_DIGITS)==3.0 || MarketInfo(L_330_st_2940,MODE_DIGITS)==5.0 ) )
   {
     L_201_do_1C98 = L_331_do_2950 * 10.0 ;
   }
   L_147_in_3B0 = MarketInfo(L_330_st_2940,MODE_DIGITS) ;
   L_1_do_0 = MarketInfo(L_330_st_2940,MODE_ASK) - MarketInfo(L_330_st_2940,MODE_BID) ;
   L_189_do_1918 = MarketInfo(L_330_st_2940,MODE_STOPLEVEL) * L_331_do_2950 ;
   L_302_do_20A8 = MarketInfo(L_330_st_2940,MODE_FREEZELEVEL) * L_331_do_2950 ;
   L_208_in_1CB8=L_57_in_148 * 60 * 60;
   if ( L_57_in_148 >  0 )
   {
     L_294_da_2080=TimeCurrent() + L_208_in_1CB8;
   }
   else
   {
     L_294_da_2080 = 0 ;
   }
   if ( Virtual_expiration )
   {
     L_294_da_2080 = 0 ;
   }
   ccbsw_20(true); 
   L_375_in_5590 ++;
 }
 else
 {
   L_330_st_2940 = Symbol() ;
   L_321_in_2910 = 0 ;
   L_331_do_2950 = SymbolInfoDouble(L_330_st_2940,16) ;
   L_201_do_1C98 = L_331_do_2950 ;
   if ( ( MarketInfo(L_330_st_2940,MODE_DIGITS)==3.0 || MarketInfo(L_330_st_2940,MODE_DIGITS)==5.0 ) )
   {
     L_201_do_1C98 = L_331_do_2950 * 10.0 ;
   }
   L_147_in_3B0 = MarketInfo(L_330_st_2940,MODE_DIGITS) ;
   L_1_do_0 = MarketInfo(L_330_st_2940,MODE_ASK) - MarketInfo(L_330_st_2940,MODE_BID) ;
   L_189_do_1918 = MarketInfo(L_330_st_2940,MODE_STOPLEVEL) * L_331_do_2950 ;
   L_302_do_20A8 = MarketInfo(L_330_st_2940,MODE_FREEZELEVEL) * L_331_do_2950 ;
   L_208_in_1CB8=L_57_in_148 * 60 * 60;
   if ( L_57_in_148 >  0 )
   {
     L_294_da_2080=TimeCurrent() + L_208_in_1CB8;
   }
   else
   {
     L_294_da_2080 = 0 ;
   }
   if ( Virtual_expiration )
   {
     L_294_da_2080 = 0 ;
   }
   ccbsw_20(true); 
 }
 if ( !(L_377_bo_55A0) )
 {
   Print("Initialisation of pairs failed!"); 
 }
 if ( L_69_do_1A0<=0.0 )
 {
   L_69_do_1A0 = 1.0 ;
 }
 if ( L_70_do_1A8<=0.0 )
 {
   L_70_do_1A8 = 1.0 ;
 }
 if ( L_79_do_200>L_78_do_1F8 )
 {
   L_79_do_200 = L_78_do_1F8 + 0.1 ;
 }
 if ( L_13_in_40<L_302_do_20A8 / L_201_do_1C98 )
 {
   L_13_in_40 = L_302_do_20A8 / L_201_do_1C98 ;
 }
 if ( L_72_do_1C0!=0.0 && L_72_do_1C0<L_302_do_20A8 / L_201_do_1C98 )
 {
   L_72_do_1C0 = L_302_do_20A8 / L_201_do_1C98 ;
 }
 if ( L_72_do_1C0!=0.0 && L_72_do_1C0<L_189_do_1918 / L_201_do_1C98 )
 {
   L_72_do_1C0 = L_189_do_1918 / L_201_do_1C98 ;
 }
 if ( L_89_do_248>0.0 && L_90_do_250<L_302_do_20A8 / L_201_do_1C98 )
 {
   L_90_do_250 = L_302_do_20A8 / L_201_do_1C98 ;
 }
 if ( L_89_do_248>0.0 && L_90_do_250<L_189_do_1918 / L_201_do_1C98 )
 {
   L_90_do_250 = L_189_do_1918 / L_201_do_1C98 ;
 }
 if ( L_69_do_1A0<L_189_do_1918 * 2.0 / L_201_do_1C98 )
 {
   L_69_do_1A0 = L_189_do_1918 * 2.0 / L_201_do_1C98 ;
 }
 if ( L_70_do_1A8<L_189_do_1918 * 2.0 / L_201_do_1C98 )
 {
   L_70_do_1A8 = L_189_do_1918 * 2.0 / L_201_do_1C98 ;
 }
 if ( L_48_do_108<L_189_do_1918 * 2.0 / L_201_do_1C98 )
 {
   L_48_do_108 = L_189_do_1918 * 2.0 / L_201_do_1C98 ;
 }
 if ( L_41_in_EC <  1 )
 {
   L_41_in_EC = 1 ;
 }
 if ( L_42_in_F0 <  1 )
 {
   L_42_in_F0 = 1 ;
 }
 if ( L_48_do_108<0.1 )
 {
   L_48_do_108 = 0.1 ;
 }
 L_208_in_1CB8=L_57_in_148 * 60 * 60;
 if ( L_57_in_148 >  0 )
 {
   L_294_da_2080=TimeCurrent() + L_208_in_1CB8;
 }
 else
 {
   L_294_da_2080 = 0 ;
 }
 if ( Virtual_expiration )
 {
   L_294_da_2080 = 0 ;
 }
 L_313_bo_20F8 = false ;
 L_243_do_1D80 = Seconds() ;
 L_312_da_20F0 = TimeCurrent() ;
 L_151_bo_3C8 = false ;
 L_152_bo_3C9 = false ;
 L_241_in_1D78 = Month() ;
 L_306_da_20C8 = iTime(L_330_st_2940,PERIOD_W1,1) ;
 L_307_da_20D0 = iTime(L_330_st_2940,PERIOD_M1,1) ;
 L_308_da_20D8 = iTime(L_330_st_2940,PERIOD_M1,1) ;
 if ( L_14_do_48>MaxSpread )
 {
   L_14_do_48 = MaxSpread ;
 }
 L_240_bo_1D75 = false ;
 ccbsw_10(L_39_in_E4); 
 ccbsw_11(L_39_in_E4); 
 L_145_do_3A0 = NormalizeDouble(L_245_do_1D90,L_147_in_3B0) ;
 L_146_do_3A8 = NormalizeDouble(L_244_do_1D88,L_147_in_3B0) ;
 L_233_in_1D28 = 0 ;
 L_239_bo_1D74 = false ;
 L_296_in_208C = L_89_do_248 * 60.0 ;
 L_100_bo_299 = false ;
 L_295_bo_2088 = true ;
 L_302_do_20A8 = MarketInfo(L_330_st_2940,MODE_FREEZELEVEL) * L_331_do_2950 ;
 if ( !(L_128_bo_354) )
 {
   L_295_bo_2088 = false ;
 }
 L_148_do_3B8 = 0.0 ;
 L_158_in_1550 = 0 ;
 L_159_in_1554 = 0 ;
 L_160_in_1558 = 0 ;
 L_161_in_155C = 0 ;
 L_217_bo_1CDA = false ;
 L_289_st_2060 = StringSubstr(L_330_st_2940,6,0) ;
 if ( Risk >  0 )
 {
   L_100_bo_299 = true ;
 }
 if ( StartLots<0.0 )
 {
   StartLots = 0.01 ;
 }
 if ( L_102_do_2A8>MarketInfo(L_330_st_2940,MODE_MAXLOT) )
 {
   L_102_do_2A8 = MarketInfo(L_330_st_2940,MODE_MAXLOT) ;
 }
 for (W_2_in = 0 ; W_2_in < L_156_in_1548 ; W_2_in ++)
 {
   for (W_3_in = 0 ; W_3_in < 2 ; W_3_in ++)
   {
     L_153_do_400_si20si2[W_2_in][W_3_in] = 0.0;
   }
 }
 for (W_4_in = 0 ; W_4_in < L_157_in_154C ; W_4_in ++)
 {
   for (W_5_in = 0 ; W_5_in < 3 ; W_5_in ++)
   {
     L_154_do_574_si100si3[W_4_in][W_5_in] = 0.0;
   }
 }
 for (W_6_in = 0 ; W_6_in < 100 ; W_6_in ++)
 {
   L_154_do_574_si100si3[W_6_in][0] = 0.0;
   L_154_do_574_si100si3[W_6_in][1] = 0.0;
 }
 L_297_bo_2090 = false ;
 L_255_do_1DD8 = iFractals(L_330_st_2940,0,1,1) ;
 L_256_do_1DE0 = iFractals(L_330_st_2940,0,2,1) ;
 L_253_do_1DC8 = L_255_do_1DD8 ;
 L_254_do_1DD0 = L_256_do_1DE0 ;
 L_258_in_1DF0 = 0 ;
 L_259_in_1DF4 = 0 ;
 L_203_bo_1CA4 = false ;
 L_280_in_1E3C = Hour() ;
 L_279_in_1E38 = 0 ;
 L_235_st_1D38=ST1_Comment + "B1";
 L_236_st_1D48=ST1_Comment + "B2";
 L_237_st_1D58=ST1_Comment + "S1";
 L_238_st_1D68=ST1_Comment + "S2";
 L_287_in_2058 = 0 ;
 L_288_in_205C = 0 ;
 L_250_in_1DB0 = Hour() ;
 if ( L_34_bo_C8 )
 {
   L_55_in_138 = 1 ;
   L_264_bo_1E08 = true ;
   L_265_bo_1E09 = true ;
 }
 L_172_in_1588 = 0 ;
 L_173_in_158C = 1083127808 ;
 L_174_in_1590 = 0 ;
 L_175_in_1594 = 0 ;
 L_290_in_2070 = 0 ;
 L_291_in_2074 = 0 ;
 L_292_in_2078 = 0 ;
 L_293_in_207C = 0 ;
 for (W_7_in = 0 ; W_7_in < 99 ; W_7_in ++)
 {
   L_315_in_22F0_si99[W_7_in] = 0;
   L_314_in_2130_si99[W_7_in] = 0;
   L_182_da_15E4_si99[W_7_in] = iTime(L_330_st_2940,L_39_in_E4,1);
   if ( !(L_192_do_195C_si99[W_7_in]<StartLots) )   continue;
   L_192_do_195C_si99[W_7_in] = StartLots;
   
 }
 L_183_in_1900 = 0 ;
 L_184_in_1904 = 0 ;
 L_215_bo_1CD8 = false ;
 L_216_bo_1CD9 = false ;
 if ( L_30_in_B0 == 1 )
 {
   L_31_do_B8 = 0.0 ;
 }
 L_147_in_3B0 = MarketInfo(L_330_st_2940,MODE_DIGITS) ;
 L_305_bo_20C0 = false ;
 IsDemo(); 
 X_st_1 = AccountName();
 StringToLower(X_st_1); 
 if ( StringFind(X_st_1,"schrynemakers",0) >= 0 && StringFind(X_st_1,"wim",0) >= 0 )
 {
   X_bo_2 = true;
 }
 else
 {   
   if ( AccountNumber() == 928189 )
   {
     X_bo_2 = true;
   }
   else
   {
     X_bo_2 = false;
   }
 }
 if ( X_bo_2 )
 {
   X_bo_3 = true;
 }
 else
 {
   X_bo_3 = false;
 }
 if ( X_bo_3 == true )
 {
   L_305_bo_20C0 = true ;
 }
 if ( ShowInfoPanel )
 {
   if ( L_108_in_2D4 == 1 )
   {
     ccbsw_28(); 
   }
   else
   {
     if ( L_108_in_2D4 == 2 )
     {
       ccbsw_29(); 
     }
   }
   ccbsw_21(); 
   ccbsw_24(); 
   ccbsw_26(); 
 }
 return(0); 
 }
//init <<==--------   --------
 void OnTick()
 {
 if ( !(L_377_bo_55A0) )   return;
 
 if ( ( StringFind(Symbol(),"XAUUSD",0) >= 0 || StringFind(Symbol(),"xauusd",0) >= 0 || StringFind(Symbol(),"GOLD",0) >= 0 || StringFind(Symbol(),"gold",0) >= 0 || StringFind(Symbol(),"Gold",0) >= 0 ) )
 {
   L_330_st_2940 = Symbol() ;
   if ( RunStrategyA )
   {
     L_39_in_E4 = 1440 ;
     L_40_in_E8 = 60 ;
     L_41_in_EC = 4 ;
     L_42_in_F0 = 2 ;
     L_45_in_F8 = 160 ;
     L_48_do_108 = 150.0 ;
     L_49_do_110 = 0.0 ;
     L_52_do_120 = -140.0 ;
     L_53_do_128 = -290.0 ;
     L_55_in_138 = 1 ;
     L_56_do_140 = 680.0 ;
     L_57_in_148 = 408 ;
     L_68_in_19C = 1 ;
     L_69_do_1A0 = 1300.0 ;
     L_70_do_1A8 = 1700.0 ;
     L_72_do_1C0 = 800.0 ;
     L_73_do_1C8 = 500.0 ;
     L_74_do_1D0 = 200.0 ;
     L_75_do_1D8 = 0.1 ;
     L_76_do_1E0 = 0.0 ;
     L_328_st_2930=ST1_Comment + "_XAUUSD_A";
     L_62_in_160=ST1_MagicNumber + 1;
     L_321_in_2910 = 0 ;
     L_331_do_2950 = SymbolInfoDouble(L_330_st_2940,16) ;
     L_201_do_1C98 = L_331_do_2950 ;
     if ( ( MarketInfo(L_330_st_2940,MODE_DIGITS)==3.0 || MarketInfo(L_330_st_2940,MODE_DIGITS)==5.0 ) )
     {
       L_201_do_1C98 = L_331_do_2950 * 10.0 ;
     }
     L_147_in_3B0 = MarketInfo(L_330_st_2940,MODE_DIGITS) ;
     L_1_do_0 = MarketInfo(L_330_st_2940,MODE_ASK) - MarketInfo(L_330_st_2940,MODE_BID) ;
     L_189_do_1918 = MarketInfo(L_330_st_2940,MODE_STOPLEVEL) * L_331_do_2950 ;
     L_302_do_20A8 = MarketInfo(L_330_st_2940,MODE_FREEZELEVEL) * L_331_do_2950 ;
     L_208_in_1CB8=L_57_in_148 * 60 * 60;
     if ( L_57_in_148 >  0 )
     {
       L_294_da_2080=TimeCurrent() + L_208_in_1CB8;
     }
     else
     {
       L_294_da_2080 = 0 ;
     }
     if ( Virtual_expiration )
     {
       L_294_da_2080 = 0 ;
     }
     ccbsw_6(0); 
   }
   if ( L_11_bo_3C )
   {
     L_39_in_E4 = 1440 ;
     L_40_in_E8 = 60 ;
     L_41_in_EC = 3 ;
     L_42_in_F0 = 2 ;
     L_45_in_F8 = 180 ;
     L_48_do_108 = 400.0 ;
     L_49_do_110 = 0.0 ;
     L_52_do_120 = 10.0 ;
     L_53_do_128 = -220.0 ;
     L_55_in_138 = 1 ;
     L_56_do_140 = 380.0 ;
     L_57_in_148 = 168 ;
     L_68_in_19C = 1 ;
     L_69_do_1A0 = 2500.0 ;
     L_70_do_1A8 = 1900.0 ;
     L_72_do_1C0 = 100.0 ;
     L_73_do_1C8 = 0.0 ;
     L_74_do_1D0 = 200.0 ;
     L_75_do_1D8 = 0.1 ;
     L_76_do_1E0 = 0.0 ;
     L_328_st_2930=ST1_Comment + "_XAUUSD_B";
     L_62_in_160=ST1_MagicNumber + 2;
     L_321_in_2910 = 1 ;
     L_331_do_2950 = SymbolInfoDouble(L_330_st_2940,16) ;
     L_201_do_1C98 = L_331_do_2950 ;
     if ( ( MarketInfo(L_330_st_2940,MODE_DIGITS)==3.0 || MarketInfo(L_330_st_2940,MODE_DIGITS)==5.0 ) )
     {
       L_201_do_1C98 = L_331_do_2950 * 10.0 ;
     }
     L_147_in_3B0 = MarketInfo(L_330_st_2940,MODE_DIGITS) ;
     L_1_do_0 = MarketInfo(L_330_st_2940,MODE_ASK) - MarketInfo(L_330_st_2940,MODE_BID) ;
     L_189_do_1918 = MarketInfo(L_330_st_2940,MODE_STOPLEVEL) * L_331_do_2950 ;
     L_302_do_20A8 = MarketInfo(L_330_st_2940,MODE_FREEZELEVEL) * L_331_do_2950 ;
     L_208_in_1CB8=L_57_in_148 * 60 * 60;
     if ( L_57_in_148 >  0 )
     {
       L_294_da_2080=TimeCurrent() + L_208_in_1CB8;
     }
     else
     {
       L_294_da_2080 = 0 ;
     }
     if ( Virtual_expiration )
     {
       L_294_da_2080 = 0 ;
     }
     ccbsw_6(1); 
   }
   if ( RunStrategyC )
   {
     L_39_in_E4 = 1440 ;
     L_40_in_E8 = 60 ;
     L_41_in_EC = 18 ;
     L_42_in_F0 = 3 ;
     L_45_in_F8 = 180 ;
     L_48_do_108 = 900.0 ;
     L_49_do_110 = 0.0 ;
     L_52_do_120 = -130.0 ;
     L_53_do_128 = -30.0 ;
     L_55_in_138 = 1 ;
     L_56_do_140 = 980.0 ;
     L_57_in_148 = 408 ;
     L_68_in_19C = 1 ;
     L_69_do_1A0 = 1200.0 ;
     L_70_do_1A8 = 1800.0 ;
     L_72_do_1C0 = 750.0 ;
     L_73_do_1C8 = 600.0 ;
     L_74_do_1D0 = 200.0 ;
     L_75_do_1D8 = 0.1 ;
     L_76_do_1E0 = 0.0 ;
     L_328_st_2930=ST1_Comment + "_XAUUSD_C";
     L_62_in_160=ST1_MagicNumber + 3;
     L_321_in_2910 = 2 ;
     L_331_do_2950 = SymbolInfoDouble(L_330_st_2940,16) ;
     L_201_do_1C98 = L_331_do_2950 ;
     if ( ( MarketInfo(L_330_st_2940,MODE_DIGITS)==3.0 || MarketInfo(L_330_st_2940,MODE_DIGITS)==5.0 ) )
     {
       L_201_do_1C98 = L_331_do_2950 * 10.0 ;
     }
     L_147_in_3B0 = MarketInfo(L_330_st_2940,MODE_DIGITS) ;
     L_1_do_0 = MarketInfo(L_330_st_2940,MODE_ASK) - MarketInfo(L_330_st_2940,MODE_BID) ;
     L_189_do_1918 = MarketInfo(L_330_st_2940,MODE_STOPLEVEL) * L_331_do_2950 ;
     L_302_do_20A8 = MarketInfo(L_330_st_2940,MODE_FREEZELEVEL) * L_331_do_2950 ;
     L_208_in_1CB8=L_57_in_148 * 60 * 60;
     if ( L_57_in_148 >  0 )
     {
       L_294_da_2080=TimeCurrent() + L_208_in_1CB8;
     }
     else
     {
       L_294_da_2080 = 0 ;
     }
     if ( Virtual_expiration )
     {
       L_294_da_2080 = 0 ;
     }
     ccbsw_6(2); 
   }
   if ( RunStrategyD )
   {
     L_39_in_E4 = 1440 ;
     L_40_in_E8 = 60 ;
     L_41_in_EC = 4 ;
     L_42_in_F0 = 2 ;
     L_45_in_F8 = 240 ;
     L_48_do_108 = 900.0 ;
     L_49_do_110 = 0.0 ;
     L_52_do_120 = -250.0 ;
     L_53_do_128 = -130.0 ;
     L_55_in_138 = 1 ;
     L_56_do_140 = 680.0 ;
     L_57_in_148 = 48 ;
     L_68_in_19C = 1 ;
     L_69_do_1A0 = 1300.0 ;
     L_70_do_1A8 = 1700.0 ;
     L_72_do_1C0 = 800.0 ;
     L_73_do_1C8 = 500.0 ;
     L_74_do_1D0 = 200.0 ;
     L_75_do_1D8 = 0.1 ;
     L_76_do_1E0 = 0.0 ;
     L_328_st_2930=ST1_Comment + "_XAUUSD_D";
     L_62_in_160=ST1_MagicNumber + 4;
     L_321_in_2910 = 3 ;
     L_331_do_2950 = SymbolInfoDouble(L_330_st_2940,16) ;
     L_201_do_1C98 = L_331_do_2950 ;
     if ( ( MarketInfo(L_330_st_2940,MODE_DIGITS)==3.0 || MarketInfo(L_330_st_2940,MODE_DIGITS)==5.0 ) )
     {
       L_201_do_1C98 = L_331_do_2950 * 10.0 ;
     }
     L_147_in_3B0 = MarketInfo(L_330_st_2940,MODE_DIGITS) ;
     L_1_do_0 = MarketInfo(L_330_st_2940,MODE_ASK) - MarketInfo(L_330_st_2940,MODE_BID) ;
     L_189_do_1918 = MarketInfo(L_330_st_2940,MODE_STOPLEVEL) * L_331_do_2950 ;
     L_302_do_20A8 = MarketInfo(L_330_st_2940,MODE_FREEZELEVEL) * L_331_do_2950 ;
     L_208_in_1CB8=L_57_in_148 * 60 * 60;
     if ( L_57_in_148 >  0 )
     {
       L_294_da_2080=TimeCurrent() + L_208_in_1CB8;
     }
     else
     {
       L_294_da_2080 = 0 ;
     }
     if ( Virtual_expiration )
     {
       L_294_da_2080 = 0 ;
     }
     ccbsw_6(3); 
   }
   if ( RunStrategyE )
   {
     L_39_in_E4 = 1440 ;
     L_40_in_E8 = 60 ;
     L_41_in_EC = 15 ;
     L_42_in_F0 = 3 ;
     L_45_in_F8 = 230 ;
     L_48_do_108 = 550.0 ;
     L_49_do_110 = 0.0 ;
     L_52_do_120 = -170.0 ;
     L_53_do_128 = -70.0 ;
     L_55_in_138 = 1 ;
     L_56_do_140 = 480.0 ;
     L_57_in_148 = 480 ;
     L_68_in_19C = 1 ;
     L_69_do_1A0 = 600.0 ;
     L_70_do_1A8 = 1700.0 ;
     L_72_do_1C0 = 500.0 ;
     L_73_do_1C8 = 300.0 ;
     L_74_do_1D0 = 200.0 ;
     L_75_do_1D8 = 0.1 ;
     L_76_do_1E0 = 0.0 ;
     L_328_st_2930=ST1_Comment + "_XAUUSD_E";
     L_62_in_160=ST1_MagicNumber + 5;
     L_321_in_2910 = 4 ;
     L_331_do_2950 = SymbolInfoDouble(L_330_st_2940,16) ;
     L_201_do_1C98 = L_331_do_2950 ;
     if ( ( MarketInfo(L_330_st_2940,MODE_DIGITS)==3.0 || MarketInfo(L_330_st_2940,MODE_DIGITS)==5.0 ) )
     {
       L_201_do_1C98 = L_331_do_2950 * 10.0 ;
     }
     L_147_in_3B0 = MarketInfo(L_330_st_2940,MODE_DIGITS) ;
     L_1_do_0 = MarketInfo(L_330_st_2940,MODE_ASK) - MarketInfo(L_330_st_2940,MODE_BID) ;
     L_189_do_1918 = MarketInfo(L_330_st_2940,MODE_STOPLEVEL) * L_331_do_2950 ;
     L_302_do_20A8 = MarketInfo(L_330_st_2940,MODE_FREEZELEVEL) * L_331_do_2950 ;
     L_208_in_1CB8=L_57_in_148 * 60 * 60;
     if ( L_57_in_148 >  0 )
     {
       L_294_da_2080=TimeCurrent() + L_208_in_1CB8;
     }
     else
     {
       L_294_da_2080 = 0 ;
     }
     if ( Virtual_expiration )
     {
       L_294_da_2080 = 0 ;
     }
     ccbsw_6(4); 
   }
   if ( RunStrategyF )
   {
     L_39_in_E4 = 1440 ;
     L_40_in_E8 = 60 ;
     L_41_in_EC = 12 ;
     L_42_in_F0 = 2 ;
     L_45_in_F8 = 50 ;
     L_48_do_108 = 700.0 ;
     L_49_do_110 = 0.0 ;
     L_52_do_120 = -210.0 ;
     L_53_do_128 = -60.0 ;
     L_55_in_138 = 1 ;
     L_56_do_140 = 30.0 ;
     L_57_in_148 = 384 ;
     L_68_in_19C = 1 ;
     L_69_do_1A0 = 1000.0 ;
     L_70_do_1A8 = 1900.0 ;
     L_72_do_1C0 = 600.0 ;
     L_73_do_1C8 = 500.0 ;
     L_74_do_1D0 = 1000.0 ;
     L_75_do_1D8 = 0.1 ;
     L_76_do_1E0 = 0.0 ;
     L_328_st_2930=ST1_Comment + "_XAUUSD_F";
     L_62_in_160=ST1_MagicNumber + 6;
     L_321_in_2910 = 5 ;
     L_331_do_2950 = SymbolInfoDouble(L_330_st_2940,16) ;
     L_201_do_1C98 = L_331_do_2950 ;
     if ( ( MarketInfo(L_330_st_2940,MODE_DIGITS)==3.0 || MarketInfo(L_330_st_2940,MODE_DIGITS)==5.0 ) )
     {
       L_201_do_1C98 = L_331_do_2950 * 10.0 ;
     }
     L_147_in_3B0 = MarketInfo(L_330_st_2940,MODE_DIGITS) ;
     L_1_do_0 = MarketInfo(L_330_st_2940,MODE_ASK) - MarketInfo(L_330_st_2940,MODE_BID) ;
     L_189_do_1918 = MarketInfo(L_330_st_2940,MODE_STOPLEVEL) * L_331_do_2950 ;
     L_302_do_20A8 = MarketInfo(L_330_st_2940,MODE_FREEZELEVEL) * L_331_do_2950 ;
     L_208_in_1CB8=L_57_in_148 * 60 * 60;
     if ( L_57_in_148 >  0 )
     {
       L_294_da_2080=TimeCurrent() + L_208_in_1CB8;
     }
     else
     {
       L_294_da_2080 = 0 ;
     }
     if ( Virtual_expiration )
     {
       L_294_da_2080 = 0 ;
     }
     ccbsw_6(5); 
   }
   if ( RunStrategyG )
   {
     L_39_in_E4 = 1440 ;
     L_40_in_E8 = 60 ;
     L_41_in_EC = 17 ;
     L_42_in_F0 = 2 ;
     L_45_in_F8 = 110 ;
     L_48_do_108 = 150.0 ;
     L_49_do_110 = 0.0 ;
     L_52_do_120 = -40.0 ;
     L_53_do_128 = -140.0 ;
     L_55_in_138 = 1 ;
     L_56_do_140 = 280.0 ;
     L_57_in_148 = 240 ;
     L_68_in_19C = 1 ;
     L_69_do_1A0 = 1200.0 ;
     L_70_do_1A8 = 1600.0 ;
     L_72_do_1C0 = 600.0 ;
     L_73_do_1C8 = 200.0 ;
     L_74_do_1D0 = 4400.0 ;
     L_75_do_1D8 = 0.1 ;
     L_76_do_1E0 = 0.0 ;
     L_328_st_2930=ST1_Comment + "_XAUUSD_G";
     L_62_in_160=ST1_MagicNumber + 7;
     L_321_in_2910 = 6 ;
     L_331_do_2950 = SymbolInfoDouble(L_330_st_2940,16) ;
     L_201_do_1C98 = L_331_do_2950 ;
     if ( ( MarketInfo(L_330_st_2940,MODE_DIGITS)==3.0 || MarketInfo(L_330_st_2940,MODE_DIGITS)==5.0 ) )
     {
       L_201_do_1C98 = L_331_do_2950 * 10.0 ;
     }
     L_147_in_3B0 = MarketInfo(L_330_st_2940,MODE_DIGITS) ;
     L_1_do_0 = MarketInfo(L_330_st_2940,MODE_ASK) - MarketInfo(L_330_st_2940,MODE_BID) ;
     L_189_do_1918 = MarketInfo(L_330_st_2940,MODE_STOPLEVEL) * L_331_do_2950 ;
     L_302_do_20A8 = MarketInfo(L_330_st_2940,MODE_FREEZELEVEL) * L_331_do_2950 ;
     L_208_in_1CB8=L_57_in_148 * 60 * 60;
     if ( L_57_in_148 >  0 )
     {
       L_294_da_2080=TimeCurrent() + L_208_in_1CB8;
     }
     else
     {
       L_294_da_2080 = 0 ;
     }
     if ( Virtual_expiration )
     {
       L_294_da_2080 = 0 ;
     }
     ccbsw_6(6); 
   }
   if ( RunStrategyH )
   {
     L_39_in_E4 = 1440 ;
     L_40_in_E8 = 60 ;
     L_41_in_EC = 7 ;
     L_42_in_F0 = 2 ;
     L_45_in_F8 = 20 ;
     L_48_do_108 = 250.0 ;
     L_49_do_110 = 0.0 ;
     L_52_do_120 = -130.0 ;
     L_53_do_128 = -120.0 ;
     L_55_in_138 = 1 ;
     L_56_do_140 = 980.0 ;
     L_57_in_148 = 432 ;
     L_68_in_19C = 1 ;
     L_69_do_1A0 = 600.0 ;
     L_70_do_1A8 = 4900.0 ;
     L_72_do_1C0 = 600.0 ;
     L_73_do_1C8 = 350.0 ;
     L_74_do_1D0 = 2000.0 ;
     L_75_do_1D8 = 0.1 ;
     L_76_do_1E0 = 0.0 ;
     L_328_st_2930=ST1_Comment + "_XAUUSD_H";
     L_62_in_160=ST1_MagicNumber + 8;
     L_321_in_2910 = 7 ;
     L_331_do_2950 = SymbolInfoDouble(L_330_st_2940,16) ;
     L_201_do_1C98 = L_331_do_2950 ;
     if ( ( MarketInfo(L_330_st_2940,MODE_DIGITS)==3.0 || MarketInfo(L_330_st_2940,MODE_DIGITS)==5.0 ) )
     {
       L_201_do_1C98 = L_331_do_2950 * 10.0 ;
     }
     L_147_in_3B0 = MarketInfo(L_330_st_2940,MODE_DIGITS) ;
     L_1_do_0 = MarketInfo(L_330_st_2940,MODE_ASK) - MarketInfo(L_330_st_2940,MODE_BID) ;
     L_189_do_1918 = MarketInfo(L_330_st_2940,MODE_STOPLEVEL) * L_331_do_2950 ;
     L_302_do_20A8 = MarketInfo(L_330_st_2940,MODE_FREEZELEVEL) * L_331_do_2950 ;
     L_208_in_1CB8=L_57_in_148 * 60 * 60;
     if ( L_57_in_148 >  0 )
     {
       L_294_da_2080=TimeCurrent() + L_208_in_1CB8;
     }
     else
     {
       L_294_da_2080 = 0 ;
     }
     if ( Virtual_expiration )
     {
       L_294_da_2080 = 0 ;
     }
     ccbsw_6(7); 
   }
 }
 else
 {
   L_330_st_2940 = Symbol() ;
   ccbsw_6(0); 
 }
 ccbsw_24(); 
 if ( iTime(Symbol(),PERIOD_M5,1) != L_376_da_5598 )
 {
   L_376_da_5598 = iTime(Symbol(),PERIOD_M5,1) ;
   if ( L_108_in_2D4 == 1 )
   {
     ccbsw_28(); 
   }
   else
   {
     if ( L_108_in_2D4 == 2 )
     {
       ccbsw_29(); 
     }
   }
   ccbsw_25(); 
   ccbsw_26(); 
 }
 L_378_in_55A4 ++;
 if ( L_378_in_55A4 < 2 )   return;
 L_311_do_20E8 = AccountBalance() ;
 L_378_in_55A4 = 0 ;
 }
//OnTick <<==--------   --------
void OnDeinit(const int reason)
 {
 ccbsw_23(); 
 return; 
}
//deinit <<==--------   --------
 int ccbsw_6( int S_0_in)
 {
  bool      W_2_bo;
  int       W_3_in;
  int       W_4_in;
//----- -----
 int        X_in_1;
 int        X_in_2;
 int        X_in_3;
 int        X_in_4;
 int        X_in_5;
 int        X_in_6;
 int        X_in_7;
 int        X_in_8;
 int        X_in_9;
 int        X_in_10;
 int        X_in_11;
 int        X_in_12;
 int        X_in_13;
 int        X_in_14;
 int        X_in_15;
 int        X_in_16;
 int        X_in_17;
 int        X_in_18;
 int        X_in_19;
 int        X_in_20;
 int        X_in_21;
 int        X_in_22;
 int        X_in_23;
 int        X_in_24;
 int        X_in_25;
 int        X_in_26;
 int        X_in_27;
 int        X_in_28;
 int        X_in_29;
 int        X_in_30;
 int        X_in_31;
 int        X_in_32;
 int        X_in_33;
 int        X_in_34;
 int        X_in_35;
 int        X_in_36;
 int        X_in_37;
 int        X_in_38;
 int        X_in_39;
 int        X_in_40;
 double     X_do_41;
 int        X_in_42;
 int        X_in_43;
 int        X_in_44;
 int        X_in_45;
 int        X_in_46;
 int        X_in_47;
 double     X_do_48;
 int        X_in_49;
 int        X_in_50;
 int        X_in_51;
 int        X_in_52;
 int        X_in_53;
 int        X_in_54;
 int        X_in_55;
 int        X_in_56;
 bool       X_bo_57;
 int        X_in_58;
 int        X_in_59;
 int        X_in_60;
 long       X_lo_61;
 long       X_lo_62;
 bool       X_bo_63;
 int        X_in_64;
 double     X_do_65;
 int        X_in_66;
 string     X_st_67;
 int        X_in_68;
 int        X_in_69;
 int        X_in_70;
 int        X_in_71;

 L_321_in_2910 = S_0_in ;
 W_2_bo = false ;
 L_305_bo_20C0 = true ;
 if ( L_49_do_110>0.0 )
 {
   L_48_do_108 = L_49_do_110 / 100.0 * MarketInfo(L_330_st_2940,MODE_ASK) * 10.0 ;
 }
 if ( L_68_in_19C == 0 )
 {
   if ( ccbsw_16() )
   {
     W_2_bo = true ;
   }
   if ( ccbsw_17() )
   {
     W_2_bo = true ;
   }
   if ( W_2_bo )
   {
     return(0); 
   }
 }
 else
 {
   if ( L_314_in_2130_si99[L_321_in_2910] != iBars(L_330_st_2940,L_68_in_19C) )
   {
     L_314_in_2130_si99[L_321_in_2910] = iBars(L_330_st_2940,L_68_in_19C);
     if ( ccbsw_16() )
     {
       W_2_bo = true ;
     }
     if ( ccbsw_17() )
     {
       W_2_bo = true ;
     }
     if ( W_2_bo )
     {
       return(0); 
     }
   }
 }
 ccbsw_20(false); 
 if ( !(IsTesting()) && MarketInfo(L_330_st_2940,MODE_TRADEALLOWED)==0.0 )
 {
   if ( !(L_239_bo_1D74) )
   {
     Print("Market closed... waiting to continue"); 
   }
   L_239_bo_1D74 = true ;
   return(0); 
 }
 if ( L_35_in_CC >  0 && ( ( Hour() == 0 && Minute() < L_35_in_CC ) || (Hour() == 23 && L_35_in_CC >  60 - L_35_in_CC) ) )
 {
   if ( !(L_239_bo_1D74) )
   {
     Print("DAYSWITCH -> Market might be closed... waiting " + string(L_35_in_CC) + " minutes before setting order.."); 
   }
   L_239_bo_1D74 = true ;
   return(0); 
 }
 L_239_bo_1D74 = false ;
 if ( L_128_bo_354 )
 {
   if ( ccbsw_18() && L_295_bo_2088 )
   {
     if ( L_130_bo_35C )
     {
       ccbsw_7(); 
     }
     L_295_bo_2088 = false ;
   }
   if ( !(ccbsw_18()) && !(L_295_bo_2088) )
   {
     Print("ENTERING NON-TRADING HOURS! Closing orders..."); 
     if ( L_130_bo_35C )
     {
       for (X_in_1 = 0 ; X_in_1 < L_157_in_154C ; X_in_1=X_in_1 + 1)
       {
         for (X_in_2 = 0 ; X_in_2 < 2 ; X_in_2=X_in_2 + 1)
         {
           L_154_do_574_si100si3[X_in_1][X_in_2] = 0.0;
         }
       }
       X_in_3 = 0;
       for (X_in_4 = OrdersTotal() ; X_in_4 >= 0 ; X_in_4=X_in_4 - 1)
       {
         if ( OrderSelect(X_in_4,0,0) != true || OrderMagicNumber() != L_62_in_160 || OrderSymbol() != L_330_st_2940 )   continue;
         
         if ( ( OrderType() != 4 && OrderType() != 5 ) )   continue;
         Print("Storing pending order nr " + string(OrderTicket())); 
         L_154_do_574_si100si3[X_in_3][1] = OrderType();
         L_154_do_574_si100si3[X_in_3][0] = OrderOpenPrice();
         L_154_do_574_si100si3[X_in_3][2] = OrderLots();
         X_in_3=X_in_3 + 1;
         
       }
     }
     X_in_5 = 1;
     for (X_in_6 = OrdersTotal() ; X_in_6 >= 0 ; X_in_6=X_in_6 - 1)
     {
       if ( OrderSelect(X_in_6,0,0) != true || OrderMagicNumber() != L_62_in_160 || OrderSymbol() != L_330_st_2940 || OrderType() != 4 )   continue;
       OrderDelete(OrderTicket(),0xFFFFFFFF); 
       
     }
     if ( X_in_5 == 2 )
     {
       for (X_in_7 = OrdersTotal() ; X_in_7 >= 0 ; X_in_7=X_in_7 - 1)
       {
         if ( OrderSelect(X_in_7,0,0) != true || OrderMagicNumber() != L_65_in_178 || OrderSymbol() != L_330_st_2940 || OrderType() != 4 )   continue;
         OrderDelete(OrderTicket(),0xFFFFFFFF); 
         
       }
     }
     X_in_8 = 1;
     for (X_in_9 = OrdersTotal() ; X_in_9 >= 0 ; X_in_9=X_in_9 - 1)
     {
       if ( OrderSelect(X_in_9,0,0) != true || OrderMagicNumber() != L_62_in_160 || OrderSymbol() != L_330_st_2940 || OrderType() != 5 )   continue;
       OrderDelete(OrderTicket(),0xFFFFFFFF); 
       
     }
     if ( X_in_8 == 2 )
     {
       for (X_in_10 = OrdersTotal() ; X_in_10 >= 0 ; X_in_10=X_in_10 - 1)
       {
         if ( OrderSelect(X_in_10,0,0) != true || OrderMagicNumber() != L_65_in_178 || OrderSymbol() != L_330_st_2940 || OrderType() != 5 )   continue;
         OrderDelete(OrderTicket(),0xFFFFFFFF); 
         
       }
     }
     X_in_11 = 2;
     if(X_in_11 == 1)
     {
     for (X_in_9 = OrdersTotal() ; X_in_9 >= 0 ; X_in_9=X_in_9 - 1)
     {
       if ( OrderSelect(X_in_9,0,0) != true || OrderMagicNumber() != L_62_in_160 || OrderSymbol() != L_330_st_2940 || OrderType() != 4 )   continue;
       OrderDelete(OrderTicket(),0xFFFFFFFF);        
     }       
     }
     if ( X_in_11 == 2 )
     {
       for (X_in_12 = OrdersTotal() ; X_in_12 >= 0 ; X_in_12=X_in_12 - 1)
       {
         if ( OrderSelect(X_in_12,0,0) != true || OrderMagicNumber() != L_65_in_178 || OrderSymbol() != L_330_st_2940 || OrderType() != 4 )   continue;
         OrderDelete(OrderTicket(),0xFFFFFFFF); 
         
       }
     }
     X_in_13 = 2;
     if(X_in_13 == 1) 
     {
     for (X_in_9 = OrdersTotal() ; X_in_9 >= 0 ; X_in_9=X_in_9 - 1)
     {
       if ( OrderSelect(X_in_9,0,0) != true || OrderMagicNumber() != L_62_in_160 || OrderSymbol() != L_330_st_2940 || OrderType() != 5 )   continue;
       OrderDelete(OrderTicket(),0xFFFFFFFF); 
       
     }       
     }
     if ( X_in_13 == 2 )
     {
       for (X_in_14 = OrdersTotal() ; X_in_14 >= 0 ; X_in_14=X_in_14 - 1)
       {
         if ( OrderSelect(X_in_14,0,0) != true || OrderMagicNumber() != L_65_in_178 || OrderSymbol() != L_330_st_2940 || OrderType() != 5 )   continue;
         OrderDelete(OrderTicket(),0xFFFFFFFF); 
         
       }
     }
     L_295_bo_2088 = true ;
     return(0); 
   }
 }
 if ( L_25_bo_95 && Day() <= 7 && DayOfWeek() == 5 )
 {
   if ( Hour() >= L_26_in_98 && Hour() <  L_27_in_9C )
   {
     X_in_15 = 1;
     for (X_in_16 = OrdersTotal() ; X_in_16 >= 0 ; X_in_16=X_in_16 - 1)
     {
       if ( OrderSelect(X_in_16,0,0) != true || OrderMagicNumber() != L_62_in_160 || OrderSymbol() != L_330_st_2940 || OrderType() != 4 )   continue;
       OrderDelete(OrderTicket(),0xFFFFFFFF); 
       
     }
     if ( X_in_15 == 2 )
     {
       for (X_in_17 = OrdersTotal() ; X_in_17 >= 0 ; X_in_17=X_in_17 - 1)
       {
         if ( OrderSelect(X_in_17,0,0) != true || OrderMagicNumber() != L_65_in_178 || OrderSymbol() != L_330_st_2940 || OrderType() != 4 )   continue;
         OrderDelete(OrderTicket(),0xFFFFFFFF); 
         
       }
     }
     X_in_18 = 1;
     for (X_in_19 = OrdersTotal() ; X_in_19 >= 0 ; X_in_19=X_in_19 - 1)
     {
       if ( OrderSelect(X_in_19,0,0) != true || OrderMagicNumber() != L_62_in_160 || OrderSymbol() != L_330_st_2940 || OrderType() != 5 )   continue;
       OrderDelete(OrderTicket(),0xFFFFFFFF); 
       
     }
     if ( X_in_18 == 2 )
     {
       for (X_in_20 = OrdersTotal() ; X_in_20 >= 0 ; X_in_20=X_in_20 - 1)
       {
         if ( OrderSelect(X_in_20,0,0) != true || OrderMagicNumber() != L_65_in_178 || OrderSymbol() != L_330_st_2940 || OrderType() != 5 )   continue;
         OrderDelete(OrderTicket(),0xFFFFFFFF); 
         
       }
     }
     X_in_21 = 2;
     if(X_in_21 == 1) 
     {
      for (X_in_16 = OrdersTotal() ; X_in_16 >= 0 ; X_in_16=X_in_16 - 1)
      {
       if ( OrderSelect(X_in_16,0,0) != true || OrderMagicNumber() != L_62_in_160 || OrderSymbol() != L_330_st_2940 || OrderType() != 4 )   continue;
       OrderDelete(OrderTicket(),0xFFFFFFFF);       
      }       
     }
     if ( X_in_21 == 2 )
     {
       for (X_in_22 = OrdersTotal() ; X_in_22 >= 0 ; X_in_22=X_in_22 - 1)
       {
         if ( OrderSelect(X_in_22,0,0) != true || OrderMagicNumber() != L_65_in_178 || OrderSymbol() != L_330_st_2940 || OrderType() != 4 )   continue;
         OrderDelete(OrderTicket(),0xFFFFFFFF); 
         
       }
     }
     X_in_23 = 2;
     if(X_in_23 == 1)
     {
     for (X_in_16 = OrdersTotal() ; X_in_16 >= 0 ; X_in_16=X_in_16 - 1)
      {
       if ( OrderSelect(X_in_16,0,0) != true || OrderMagicNumber() != L_62_in_160 || OrderSymbol() != L_330_st_2940 || OrderType() != 5 )   continue;
       OrderDelete(OrderTicket(),0xFFFFFFFF); 
       
      }       
     }
     if ( X_in_23 == 2 )
     {
       for (X_in_24 = OrdersTotal() ; X_in_24 >= 0 ; X_in_24=X_in_24 - 1)
       {
         if ( OrderSelect(X_in_24,0,0) != true || OrderMagicNumber() != L_65_in_178 || OrderSymbol() != L_330_st_2940 || OrderType() != 5 )   continue;
         OrderDelete(OrderTicket(),0xFFFFFFFF); 
         
       }
     }
     if ( !(L_313_bo_20F8) )
     {
       Print("NFP!! deleting trades!!"); 
     }
     L_313_bo_20F8 = true ;
   }
   else
   {
     L_313_bo_20F8 = false ;
   }
 }
 if ( L_313_bo_20F8 )
 {
   return(0); 
 }
 if ( L_22_bo_8C )
 {
   if ( DayOfWeek() == 5 && Hour() >= L_23_in_90 && !(L_297_bo_2090) )
   {
     if ( L_24_bo_94 )
     {
       for (X_in_25 = 0 ; X_in_25 < L_157_in_154C ; X_in_25=X_in_25 + 1)
       {
         for (X_in_26 = 0 ; X_in_26 < 2 ; X_in_26=X_in_26 + 1)
         {
           L_154_do_574_si100si3[X_in_25][X_in_26] = 0.0;
         }
       }
       X_in_27 = 0;
       for (X_in_28 = OrdersTotal() ; X_in_28 >= 0 ; X_in_28=X_in_28 - 1)
       {
         if ( OrderSelect(X_in_28,0,0) != true || OrderMagicNumber() != L_62_in_160 || OrderSymbol() != L_330_st_2940 )   continue;
         
         if ( ( OrderType() != 4 && OrderType() != 5 ) )   continue;
         Print("Storing pending order nr " + string(OrderTicket())); 
         L_154_do_574_si100si3[X_in_27][1] = OrderType();
         L_154_do_574_si100si3[X_in_27][0] = OrderOpenPrice();
         L_154_do_574_si100si3[X_in_27][2] = OrderLots();
         X_in_27=X_in_27 + 1;
         
       }
     }
     X_in_29 = 1;
     for (X_in_30 = OrdersTotal() ; X_in_30 >= 0 ; X_in_30=X_in_30 - 1)
     {
       if ( OrderSelect(X_in_30,0,0) != true || OrderMagicNumber() != L_62_in_160 || OrderSymbol() != L_330_st_2940 || OrderType() != 4 )   continue;
       OrderDelete(OrderTicket(),0xFFFFFFFF); 
       
     }
     if ( X_in_29 == 2 )
     {
       for (X_in_31 = OrdersTotal() ; X_in_31 >= 0 ; X_in_31=X_in_31 - 1)
       {
         if ( OrderSelect(X_in_31,0,0) != true || OrderMagicNumber() != L_65_in_178 || OrderSymbol() != L_330_st_2940 || OrderType() != 4 )   continue;
         OrderDelete(OrderTicket(),0xFFFFFFFF); 
         
       }
     }
     X_in_32 = 1;
     for (X_in_33 = OrdersTotal() ; X_in_33 >= 0 ; X_in_33=X_in_33 - 1)
     {
       if ( OrderSelect(X_in_33,0,0) != true || OrderMagicNumber() != L_62_in_160 || OrderSymbol() != L_330_st_2940 || OrderType() != 5 )   continue;
       OrderDelete(OrderTicket(),0xFFFFFFFF); 
       
     }
     if ( X_in_32 == 2 )
     {
       for (X_in_34 = OrdersTotal() ; X_in_34 >= 0 ; X_in_34=X_in_34 - 1)
       {
         if ( OrderSelect(X_in_34,0,0) != true || OrderMagicNumber() != L_65_in_178 || OrderSymbol() != L_330_st_2940 || OrderType() != 5 )   continue;
         OrderDelete(OrderTicket(),0xFFFFFFFF); 
         
       }
     }
     X_in_35 = 2;
     if(X_in_35 == 1) 
     {
     for (X_in_30 = OrdersTotal() ; X_in_30 >= 0 ; X_in_30=X_in_30 - 1)
     {
       if ( OrderSelect(X_in_30,0,0) != true || OrderMagicNumber() != L_62_in_160 || OrderSymbol() != L_330_st_2940 || OrderType() != 4 )   continue;
       OrderDelete(OrderTicket(),0xFFFFFFFF); 
       
     }     
     }
     if ( X_in_35 == 2 )
     {
       for (X_in_36 = OrdersTotal() ; X_in_36 >= 0 ; X_in_36=X_in_36 - 1)
       {
         if ( OrderSelect(X_in_36,0,0) != true || OrderMagicNumber() != L_65_in_178 || OrderSymbol() != L_330_st_2940 || OrderType() != 4 )   continue;
         OrderDelete(OrderTicket(),0xFFFFFFFF); 
         
       }
     }
     X_in_37 = 2;
     if(X_in_37 == 1) 
     {
     for (X_in_30 = OrdersTotal() ; X_in_30 >= 0 ; X_in_30=X_in_30 - 1)
     {
       if ( OrderSelect(X_in_30,0,0) != true || OrderMagicNumber() != L_62_in_160 || OrderSymbol() != L_330_st_2940 || OrderType() != 5 )   continue;
       OrderDelete(OrderTicket(),0xFFFFFFFF); 
       
     }      
     }
     if ( X_in_37 == 2 )
     {
       for (X_in_38 = OrdersTotal() ; X_in_38 >= 0 ; X_in_38=X_in_38 - 1)
       {
         if ( OrderSelect(X_in_38,0,0) != true || OrderMagicNumber() != L_65_in_178 || OrderSymbol() != L_330_st_2940 || OrderType() != 5 )   continue;
         OrderDelete(OrderTicket(),0xFFFFFFFF); 
         
       }
     }
     Print("Weekend starting! Stopping trades.."); 
     L_297_bo_2090 = true ;
     return(0); 
   }
   if ( DayOfWeek() != 5 && L_297_bo_2090 == true )
   {
     L_297_bo_2090 = false ;
     if ( L_24_bo_94 )
     {
       ccbsw_7(); 
       return(0); 
     }
   }
 }
 L_1_do_0 = MarketInfo(L_330_st_2940,MODE_ASK) - MarketInfo(L_330_st_2940,MODE_BID) ;
 if ( L_12_bo_3D )
 {
   if ( L_1_do_0>MaxSpread * L_201_do_1C98 )
   {
     ccbsw_8(); 
     return(0); 
   }
   if ( L_1_do_0<=L_14_do_48 * L_201_do_1C98 && ( !(L_22_bo_8C) || DayOfWeek() != 5 || Hour() <  L_23_in_90 ) && ( !(L_128_bo_354) || ccbsw_18() ) )
   {
     ccbsw_7(); 
   }
 }
 if ( L_37_in_D4 == 1 )
 {
   X_in_39 = 0;
   for (X_in_40 = OrdersTotal() ; X_in_40 >= 0 ; X_in_40=X_in_40 - 1)
   {
     if ( OrderSelect(X_in_40,0,0) != true || OrderMagicNumber() != L_62_in_160 || OrderSymbol() != L_330_st_2940 || OrderType() != 4 )   continue;
     X_in_39=X_in_39 + 1;
     
   }
   if ( X_in_39 >  L_55_in_138 )
   {
     X_do_41 = 0.0;
     X_in_42 = 0;
     for (X_in_43 = OrdersTotal() ; X_in_43 >= 0 ; X_in_43=X_in_43 - 1)
     {
       if ( OrderSelect(X_in_43,0,0) != true || OrderMagicNumber() != L_62_in_160 || OrderSymbol() != L_330_st_2940 || OrderType() != 4 || !(OrderOpenPrice()>X_do_41) )   continue;
       X_in_42 = OrderTicket();
       X_do_41 = OrderOpenPrice();
       
     }
     if ( X_in_42 != 0 )
     {
       OrderDelete(X_in_42,Green); 
       X_in_44 = X_in_42;
       for (X_in_45 = 0 ; X_in_45 < 100 ; X_in_45=X_in_45 + 1)
       {
         if ( !(L_155_do_F08_si100si2[X_in_45][0]==X_in_44) )   continue;
         L_155_do_F08_si100si2[X_in_45][0] = 0.0;
         L_155_do_F08_si100si2[X_in_45][1] = 0.0;
         break;
         
       }
       Print("Max number of pending buy orders reached... deleting highest buystop order!"); 
     }
   }
   X_in_46 = 0;
   for (X_in_47 = OrdersTotal() ; X_in_47 >= 0 ; X_in_47=X_in_47 - 1)
   {
     if ( OrderSelect(X_in_47,0,0) != true || OrderMagicNumber() != L_62_in_160 || OrderSymbol() != L_330_st_2940 || OrderType() != 5 )   continue;
     X_in_46=X_in_46 + 1;
     
   }
   if ( X_in_46 >  L_55_in_138 )
   {
     X_do_48 = 9999.0;
     X_in_49 = 0;
     for (X_in_50 = OrdersTotal() ; X_in_50 >= 0 ; X_in_50=X_in_50 - 1)
     {
       if ( OrderSelect(X_in_50,0,0) != true || OrderMagicNumber() != L_62_in_160 || OrderSymbol() != L_330_st_2940 || OrderType() != 5 || !(OrderOpenPrice()<X_do_48) )   continue;
       X_in_49 = OrderTicket();
       X_do_48 = OrderOpenPrice();
       
     }
     if ( X_in_49 != 0 )
     {
       OrderDelete(X_in_49,Green); 
       X_in_51 = X_in_49;
       for (X_in_52 = 0 ; X_in_52 < 100 ; X_in_52=X_in_52 + 1)
       {
         if ( !(L_155_do_F08_si100si2[X_in_52][0]==X_in_51) )   continue;
         L_155_do_F08_si100si2[X_in_52][0] = 0.0;
         L_155_do_F08_si100si2[X_in_52][1] = 0.0;
         break;
         
       }
       Print("Max number of pending sell orders reached... deleting lowest sellstop order!"); 
     }
   }
 }
 if ( !(L_297_bo_2090) && L_37_in_D4 == 1 && !(L_295_bo_2088) )
 {
   if ( ( L_315_in_22F0_si99[L_321_in_2910] != iBars(L_330_st_2940,L_40_in_E8) || L_40_in_E8 == 0 ) )
   {
     L_315_in_22F0_si99[L_321_in_2910] = iBars(L_330_st_2940,L_40_in_E8);
     if ( L_84_in_220 >  0 && L_85_in_224 >= 0 )
     {
       L_218_do_1CE0 = L_87_do_230 * L_201_do_1C98 + (ccbsw_12(L_82_in_218,L_84_in_220,L_85_in_224) + L_1_do_0) ;
       L_219_do_1CE8 = ccbsw_13(L_82_in_218,L_84_in_220,L_85_in_224) - L_87_do_230 * L_201_do_1C98 ;
     }
     if ( L_144_in_39C >  0 )
     {
       W_3_in=MathRand() * L_144_in_39C / 32768 + 1;
       L_7_in_18 = W_3_in ;
       Print("Slippage: " + string(W_3_in)); 
     }
     if ( L_30_in_B0 != 1 )
     {
       X_in_53 = 0;
       for (X_in_54 = OrdersTotal() ; X_in_54 >= 0 ; X_in_54=X_in_54 - 1)
       {
         if ( OrderSelect(X_in_54,0,0) != true || OrderMagicNumber() != L_62_in_160 || OrderSymbol() != L_330_st_2940 || OrderType() != 0 )   continue;
         X_in_53=X_in_53 + 1;
         
       }
       if ( X_in_53 == 0 )
       {
         X_in_55 = 0;
         for (X_in_56 = OrdersTotal() ; X_in_56 >= 0 ; X_in_56=X_in_56 - 1)
         {
           if ( OrderSelect(X_in_56,0,0) != true || OrderMagicNumber() != L_62_in_160 || OrderSymbol() != L_330_st_2940 || OrderType() != 1 )   continue;
           X_in_55=X_in_55 + 1;
           
         }
         if ( X_in_55 == 0 )
         {
           X_bo_57 = false;
           for (X_in_58 = 0 ; X_in_58 < L_156_in_1548 ; X_in_58=X_in_58 + 1)
           {
             if ( !(L_153_do_400_si20si2[X_in_58][0]>0.0) )   continue;
             X_bo_57 = false;
             for (X_in_59 = OrdersTotal() ; X_in_59 >= 0 ; X_in_59=X_in_59 - 1)
             {
               if ( OrderSelect(X_in_59,0,0) != true )   continue;
               
               if ( ( OrderType() != 0 && OrderType() != 1 ) || !(OrderTicket()==L_153_do_400_si20si2[X_in_58][0]) )   continue;
               X_bo_57 = true;
               
             }
             if ( X_bo_57 )   continue;
             L_153_do_400_si20si2[X_in_58][0] = 0.0;
             L_153_do_400_si20si2[X_in_58][1] = 0.0;
             
           }
         }
       }
     }
     for (W_4_in = 0 ; W_4_in < L_55_in_138 ; W_4_in ++)
     {
       if ( L_180_bo_15A8 )
       {
         L_251_do_1DB8 = iMA(L_330_st_2940,0,L_181_in_15AC,0,1,0,1) ;
         L_252_do_1DC0 = iMA(L_330_st_2940,0,L_185_in_1908,0,1,0,1) ;
       }
       ccbsw_9(L_69_do_1A0,L_61_in_15C); 
       if ( L_192_do_195C_si99[L_321_in_2910]>L_102_do_2A8 )
       {
         L_192_do_195C_si99[L_321_in_2910] = L_102_do_2A8;
       }
       if ( L_57_in_148 >  0 )
       {
         L_294_da_2080=TimeCurrent() + L_208_in_1CB8;
       }
       if ( Virtual_expiration )
       {
         L_294_da_2080 = 0 ;
         for (X_in_60 = OrdersTotal() ; X_in_60 >= 0 ; X_in_60=X_in_60 - 1)
         {
           if ( OrderSelect(X_in_60,0,0) != true || OrderMagicNumber() != L_62_in_160 || OrderSymbol() != L_330_st_2940 )   continue;
           
           if ( ( OrderType() != 4 && OrderType() != 5 ) )   continue;
           X_lo_61 = TimeCurrent();
           X_lo_62=OrderOpenTime() + L_208_in_1CB8;
           if ( X_lo_61 < X_lo_62 )   continue;
           OrderDelete(OrderTicket(),Red); 
           
         }
       }
       ccbsw_14(1); 
       ccbsw_15(1); 
     }
   }
   ccbsw_26(); 
   if ( L_250_in_1DB0 != Hour() )
   {
     L_250_in_1DB0 = Hour() ;
     X_bo_63 = false;
     for (X_in_64 = 0 ; X_in_64 < 100 ; X_in_64=X_in_64 + 1)
     {
       X_do_65 = L_155_do_F08_si100si2[X_in_64][0];
       X_bo_63 = false;
       for (X_in_66 = OrdersTotal() ; X_in_66 >= 0 ; X_in_66=X_in_66 - 1)
       {
         if ( !(OrderSelect(X_in_66,0,0)) || X_do_65 != OrderTicket() )   continue;
         X_bo_63 = true;
         
       }
       if ( X_bo_63 )   continue;
       L_155_do_F08_si100si2[X_in_64][0] = 0.0;
       L_155_do_F08_si100si2[X_in_64][1] = 0.0;
       
     }
   }
 }
 if ( L_29_bo_AC )
 {
   X_st_67="Current spread: " + string(NormalizeDouble(L_1_do_0 / L_201_do_1C98,1)) + "\nPending Buy Order: ";
   X_in_68 = 0;
   for (X_in_69 = OrdersTotal() ; X_in_69 >= 0 ; X_in_69=X_in_69 - 1)
   {
     if ( OrderSelect(X_in_69,0,0) != true || OrderMagicNumber() != L_62_in_160 || OrderSymbol() != L_330_st_2940 || OrderType() != 4 )   continue;
     X_in_68=X_in_68 + 1;
     
   }
   X_st_67=X_st_67 + string(X_in_68);
   X_st_67=X_st_67 + "\nPending Sell Orders: ";
   X_in_70 = 0;
   for (X_in_71 = OrdersTotal() ; X_in_71 >= 0 ; X_in_71=X_in_71 - 1)
   {
     if ( OrderSelect(X_in_71,0,0) != true || OrderMagicNumber() != L_62_in_160 || OrderSymbol() != L_330_st_2940 || OrderType() != 5 )   continue;
     X_in_70=X_in_70 + 1;
     
   }
   X_st_67=X_st_67 + string(X_in_70);
   Comment(X_st_67); 
 }
 return(0); 
 }
//ccbsw_6 <<==--------   --------
 void ccbsw_7()
 {
  int       W_1_in;
//----- -----
 double     X_do_1;
 int        X_in_2;
 int        X_in_3;
 double     X_do_4;
 int        X_in_5;
 int        X_in_6;
 double     X_do_7;
 int        X_in_8;
 int        X_in_9;
 double     X_do_10;
 int        X_in_11;
 int        X_in_12;
 int        X_in_13;

 for (W_1_in = 0 ; W_1_in < L_157_in_154C ; W_1_in ++)
 {
   if ( !(L_154_do_574_si100si3[W_1_in][0]>0.0) )   continue;
   
   if ( L_154_do_574_si100si3[W_1_in][1]==4.0 && MarketInfo(L_330_st_2940,MODE_ASK)<L_154_do_574_si100si3[W_1_in][0] - L_189_do_1918 )
   {
     Print("Restoring pending buy-order"); 
     L_202_in_1CA0 = OrderSend(L_330_st_2940,4,L_154_do_574_si100si3[W_1_in][2],L_154_do_574_si100si3[W_1_in][0],int(L_15_do_50 * L_201_do_1C98),L_154_do_574_si100si3[W_1_in][0] - (L_69_do_1A0 + L_31_do_B8) * L_201_do_1C98,L_70_do_1A8 * L_201_do_1C98 + L_154_do_574_si100si3[W_1_in][0],L_328_st_2930,L_62_in_160,L_294_da_2080 + 172800,Green) ;
     L_266_bo_1E0A = false ;
     X_do_1 = L_154_do_574_si100si3[W_1_in][0];
     X_in_2 = L_202_in_1CA0;
     for (X_in_3 = 0 ; X_in_3 < 100 ; X_in_3=X_in_3 + 1)
     {
       if ( !(L_155_do_F08_si100si2[X_in_3][0]==0.0) )   continue;
       L_155_do_F08_si100si2[X_in_3][0] = X_in_2;
       L_155_do_F08_si100si2[X_in_3][1] = X_do_1;
       break;
       
     }
     if ( L_202_in_1CA0 <= 0 )
     {
       if ( GetLastError() == 132 )
       {
         ResetLastError();
         if(1==0) //条件不成立
         {
           do
           {
             Sleep(2500); 
             L_202_in_1CA0 = OrderSend(L_330_st_2940,4,L_154_do_574_si100si3[W_1_in][2],L_154_do_574_si100si3[W_1_in][0],int(L_15_do_50 * L_201_do_1C98),L_154_do_574_si100si3[W_1_in][0] - (L_69_do_1A0 + L_31_do_B8) * L_201_do_1C98,L_70_do_1A8 * L_201_do_1C98 + L_154_do_574_si100si3[W_1_in][0],L_328_st_2930,L_62_in_160,L_294_da_2080 + 172800,Green) ;
             L_266_bo_1E0A = false ;
             X_do_4 = L_154_do_574_si100si3[W_1_in][0];
             X_in_5 = L_202_in_1CA0;
             for (X_in_6 = 0 ; X_in_6 < 100 ; X_in_6=X_in_6 + 1)
             {
               if ( !(L_155_do_F08_si100si2[X_in_6][0]==0.0) )   continue;
               L_155_do_F08_si100si2[X_in_6][0] = X_in_5;
               L_155_do_F08_si100si2[X_in_6][1] = X_do_4;
               break;
               
             }
           }
           while(GetLastError() == 132);
           
         }
       }
       Print("error: \'" + ccbsw_19(GetLastError()) + "\' when setting entry order"); 
     }
   }
   if ( !(L_154_do_574_si100si3[W_1_in][1]==5.0) || !(MarketInfo(L_330_st_2940,MODE_BID)>L_154_do_574_si100si3[W_1_in][0] + L_189_do_1918) )   continue;
   Print("Restoring pending sell-order"); 
   L_202_in_1CA0 = OrderSend(L_330_st_2940,5,L_154_do_574_si100si3[W_1_in][2],L_154_do_574_si100si3[W_1_in][0],int(L_15_do_50 * L_201_do_1C98),(L_69_do_1A0 + L_31_do_B8) * L_201_do_1C98 + L_154_do_574_si100si3[W_1_in][0],L_154_do_574_si100si3[W_1_in][0] - L_70_do_1A8 * L_201_do_1C98,L_328_st_2930,L_62_in_160,L_294_da_2080 + 172800,Green) ;
   L_267_bo_1E0B = false ;
   X_do_7 = L_154_do_574_si100si3[W_1_in][0];
   X_in_8 = L_202_in_1CA0;
   for (X_in_9 = 0 ; X_in_9 < 100 ; X_in_9=X_in_9 + 1)
   {
     if ( !(L_155_do_F08_si100si2[X_in_9][0]==0.0) )   continue;
     L_155_do_F08_si100si2[X_in_9][0] = X_in_8;
     L_155_do_F08_si100si2[X_in_9][1] = X_do_7;
     break;
     
   }
   if ( L_202_in_1CA0 > 0 )   continue;
   
   if ( GetLastError() == 132 )
   {
     ResetLastError();
     if(1==0) //条件不成立
     {
       do
       {
         Sleep(2500); 
         L_202_in_1CA0 = OrderSend(L_330_st_2940,5,L_154_do_574_si100si3[W_1_in][2],L_154_do_574_si100si3[W_1_in][0],int(L_15_do_50 * L_201_do_1C98),(L_69_do_1A0 + L_31_do_B8) * L_201_do_1C98 + L_154_do_574_si100si3[W_1_in][0],L_154_do_574_si100si3[W_1_in][0] - L_70_do_1A8 * L_201_do_1C98,L_328_st_2930,L_62_in_160,L_294_da_2080 + 172800,Green) ;
         L_267_bo_1E0B = false ;
         X_do_10 = L_154_do_574_si100si3[W_1_in][0];
         X_in_11 = L_202_in_1CA0;
         for (X_in_12 = 0 ; X_in_12 < 100 ; X_in_12=X_in_12 + 1)
         {
           if ( !(L_155_do_F08_si100si2[X_in_12][0]==0.0) )   continue;
           L_155_do_F08_si100si2[X_in_12][0] = X_in_11;
           L_155_do_F08_si100si2[X_in_12][1] = X_do_10;
           break;
           
         }
       }
       while(GetLastError() == 132);
       
     }
   }
   Print("error: \'" + ccbsw_19(GetLastError()) + "\' when setting entry order"); 
   
 }
 for (X_in_13 = 0 ; X_in_13 < L_157_in_154C ; X_in_13=X_in_13 + 1)
 {
   L_154_do_574_si100si3[X_in_13][0] = 0.0;
   L_154_do_574_si100si3[X_in_13][1] = 0.0;
   L_154_do_574_si100si3[X_in_13][2] = 0.0;
 }
 }
//ccbsw_7 <<==--------   --------
 int ccbsw_8()
 {
  int       W_2_in;
  int       W_3_in;
  int       W_4_in;
//----- -----
 int        X_in_1;
 int        X_in_2;
 int        X_in_3;
 int        X_in_4;
 double     X_do_5;
 double     X_do_6;
 int        X_in_7;
 int        X_in_8;
 int        X_in_9;
 int        X_in_10;

 for (W_2_in = OrdersTotal() ; W_2_in >= 0 ; W_2_in --)
 {
   if ( OrderSelect(W_2_in,0,0) != true )   continue;
   
   if ( ( OrderMagicNumber() != L_62_in_160 && OrderMagicNumber() != L_65_in_178 ) || OrderSymbol() != L_330_st_2940 )   continue;
   
   if ( OrderType() == 4 && OrderOpenPrice()<L_13_in_40 * L_201_do_1C98 + MarketInfo(L_330_st_2940,MODE_ASK) && MarketInfo(L_330_st_2940,MODE_ASK)<OrderOpenPrice() - L_302_do_20A8 )
   {
     if ( L_14_do_48>0.0 )
     {
       Print("Spread too high..(" + string(L_1_do_0) + ") storing and deleting order " + string(OrderTicket())); 
       for (W_3_in = 0 ; W_3_in < L_157_in_154C ; W_3_in ++)
       {
         if ( L_154_do_574_si100si3[W_3_in][0]==0.0 )
         {
           Print("Storing pending order nr " + string(OrderTicket())); 
           L_154_do_574_si100si3[W_3_in][1] = OrderType();
           L_154_do_574_si100si3[W_3_in][0] = OrderOpenPrice();
           L_154_do_574_si100si3[W_3_in][2] = OrderLots();
           break;
         }
       }
       X_in_1 = OrderTicket();
       for (X_in_2 = 0 ; X_in_2 < 100 ; X_in_2=X_in_2 + 1)
       {
         if ( !(L_155_do_F08_si100si2[X_in_2][0]==X_in_1) )   continue;
         L_155_do_F08_si100si2[X_in_2][0] = 0.0;
         L_155_do_F08_si100si2[X_in_2][1] = 0.0;
         break;
         
       }
       OrderDelete(OrderTicket(),Green); 
     }
     else
     {
       Print("Spread too high..(" + string(L_1_do_0) + ") deleting order " + string(OrderTicket())); 
       X_in_3 = OrderTicket();
       for (X_in_4 = 0 ; X_in_4 < 100 ; X_in_4=X_in_4 + 1)
       {
         if ( !(L_155_do_F08_si100si2[X_in_4][0]==X_in_3) )   continue;
         L_155_do_F08_si100si2[X_in_4][0] = 0.0;
         L_155_do_F08_si100si2[X_in_4][1] = 0.0;
         break;
         
       }
       OrderDelete(OrderTicket(),Green); 
     }
   }
   if ( OrderType() != 5 )   continue;
   X_do_5 = OrderOpenPrice();
   if ( !(X_do_5>MarketInfo(L_330_st_2940,MODE_BID) - L_13_in_40 * L_201_do_1C98) )   continue;
   X_do_6 = MarketInfo(L_330_st_2940,MODE_BID);
   if ( !(X_do_6>OrderOpenPrice() + L_302_do_20A8) )   continue;
   
   if ( L_14_do_48>0.0 )
   {
     Print("Spread too high..(" + string(L_1_do_0) + ") storing and deleting order " + string(OrderTicket())); 
     for (W_4_in = 0 ; W_4_in < L_157_in_154C ; W_4_in ++)
     {
       if ( L_154_do_574_si100si3[W_4_in][0]==0.0 )
       {
         Print("Storing pending order nr " + string(OrderTicket())); 
         L_154_do_574_si100si3[W_4_in][1] = OrderType();
         L_154_do_574_si100si3[W_4_in][0] = OrderOpenPrice();
         L_154_do_574_si100si3[W_4_in][2] = OrderLots();
         break;
       }
     }
     X_in_7 = OrderTicket();
     for (X_in_8 = 0 ; X_in_8 < 100 ; X_in_8=X_in_8 + 1)
     {
       if ( !(L_155_do_F08_si100si2[X_in_8][0]==X_in_7) )   continue;
       L_155_do_F08_si100si2[X_in_8][0] = 0.0;
       L_155_do_F08_si100si2[X_in_8][1] = 0.0;
       break;
       
     }
     OrderDelete(OrderTicket(),Green); 
      continue;
   }
   Print("Spread too high..(" + string(L_1_do_0) + ") deleting order " + string(OrderTicket())); 
   X_in_9 = OrderTicket();
   for (X_in_10 = 0 ; X_in_10 < 100 ; X_in_10=X_in_10 + 1)
   {
     if ( !(L_155_do_F08_si100si2[X_in_10][0]==X_in_9) )   continue;
     L_155_do_F08_si100si2[X_in_10][0] = 0.0;
     L_155_do_F08_si100si2[X_in_10][1] = 0.0;
     break;
     
   }
   OrderDelete(OrderTicket(),Green); 
   
 }
 return(false);//W_1_bo = false ;
 }
//ccbsw_8 <<==--------   --------
 void ccbsw_9( double S_0_do,int S_1_in)
 {
  double    W_1_do;
  double    W_2_do;
  double    W_3_do;
  double    W_4_do;
  double    W_5_do;
  double    W_6_do;
  double    W_7_do;
//----- -----

 W_1_do = L_192_do_195C_si99[L_321_in_2910] ;
 W_2_do = L_192_do_195C_si99[L_321_in_2910] ;
 W_3_do = AccountBalance() ;
 if ( UseEquity )
 {
   W_3_do = AccountEquity() ;
 }
 W_4_do = S_0_do ;
 if ( ( L_147_in_3B0 == 2 || L_147_in_3B0 == 4 ) )
 {
   W_4_do = S_0_do / 10.0 ;
 }
 if ( Risk <  999 && Risk >  0 )
 {
   W_5_do = Risk ;
   W_6_do = W_5_do / 1000.0 * W_3_do ;
   if ( MarketInfo(L_330_st_2940,MODE_LOTSTEP)==0.1 )
   {
     W_2_do = NormalizeDouble(S_1_in * 0.01 * (W_6_do / (MarketInfo(L_330_st_2940,MODE_TICKVALUE) * W_4_do) * 0.1),1) ;
   }
   if ( MarketInfo(L_330_st_2940,MODE_LOTSTEP)==0.01 )
   {
     W_2_do = NormalizeDouble(S_1_in * 0.01 * (W_6_do / (MarketInfo(L_330_st_2940,MODE_TICKVALUE) * W_4_do) * 0.1),2) ;
   }
 }
 if ( Risk == 999 )
 {
   W_7_do = Manual_RiskPerTrade / 100.0 * W_3_do ;
   if ( MarketInfo(L_330_st_2940,MODE_LOTSTEP)==0.1 )
   {
     W_2_do = NormalizeDouble(S_1_in * 0.01 * (W_7_do / (MarketInfo(L_330_st_2940,MODE_TICKVALUE) * W_4_do) * 0.1),1) ;
   }
   if ( MarketInfo(L_330_st_2940,MODE_LOTSTEP)==0.01 )
   {
     W_2_do = NormalizeDouble(S_1_in * 0.01 * (W_7_do / (MarketInfo(L_330_st_2940,MODE_TICKVALUE) * W_4_do) * 0.1),2) ;
   }
 }
 if ( Risk == 0 )
 {
   if ( MarketInfo(L_330_st_2940,MODE_LOTSTEP)==0.1 )
   {
     W_2_do = NormalizeDouble(S_1_in * 0.01 * StartLots,1) ;
   }
   if ( MarketInfo(L_330_st_2940,MODE_LOTSTEP)==0.01 )
   {
     W_2_do = NormalizeDouble(S_1_in * 0.01 * StartLots,2) ;
   }
 }
 if ( Risk == 9999 )
 {
   if ( MarketInfo(L_330_st_2940,MODE_LOTSTEP)==0.1 )
   {
     W_2_do = NormalizeDouble(S_1_in * 0.01 * (W_3_do / LotPerBalance_step * 0.01),1) ;
   }
   if ( MarketInfo(L_330_st_2940,MODE_LOTSTEP)==0.01 )
   {
     W_2_do = NormalizeDouble(S_1_in * 0.01 * (W_3_do / LotPerBalance_step * 0.01),2) ;
   }
 }
 if ( Risk == 99999 )
 {
   if ( SymbolInfoDouble(L_330_st_2940,36)==0.1 )
   {
     W_2_do = NormalizeDouble(L_104_do_2B8 / L_332_do_2958 * AccountInfoDouble(ACCOUNT_BALANCE) / 100.0 * 0.01,1) ;
   }
   if ( SymbolInfoDouble(L_330_st_2940,36)==0.01 )
   {
     W_2_do = NormalizeDouble(L_104_do_2B8 / L_332_do_2958 * AccountInfoDouble(ACCOUNT_BALANCE) / 100.0 * 0.01,2) ;
   }
 }
 if ( W_2_do<MarketInfo(L_330_st_2940,MODE_LOTSTEP) )
 {
   W_2_do = MarketInfo(L_330_st_2940,MODE_LOTSTEP) ;
 }
 if ( W_2_do<StartLots )
 {
   W_2_do = StartLots ;
 }
 if ( W_2_do>L_102_do_2A8 )
 {
   W_2_do = L_102_do_2A8 ;
 }
 if ( OnlyUp && W_2_do<W_1_do )
 {
   W_2_do = W_1_do ;
 }
 if ( W_2_do<MarketInfo(L_330_st_2940,MODE_MINLOT) )
 {
   Print("Minimum lotsize (" + L_330_st_2940 + ") for this broker is " + string(MarketInfo(L_330_st_2940,MODE_MINLOT)) + " lots!!"); 
 }
 if ( W_2_do>MarketInfo(L_330_st_2940,MODE_MAXLOT) && MarketInfo(L_330_st_2940,MODE_MAXLOT)!=0.0 )
 {
   Print("Maximum lotsize for this broker is " + string(MarketInfo(L_330_st_2940,MODE_MAXLOT)) + " lots!!"); 
   W_2_do = MarketInfo(L_330_st_2940,MODE_MAXLOT) ;
 }
 if ( MarketInfo(L_330_st_2940,MODE_LOTSTEP)==0.1 )
 {
   L_192_do_195C_si99[L_321_in_2910] = NormalizeDouble((MathFloor(W_2_do * 10.0)) / 10.0,1);
   return;
 }
 L_192_do_195C_si99[L_321_in_2910] = NormalizeDouble(MathFloor(W_2_do * 100.0) / 100.0,2);
 }
//ccbsw_9 <<==--------   --------
 double ccbsw_10( int S_0_in)
 {
  bool      W_2_bo = false;
  bool      W_3_bo = false;
  bool      W_4_bo;
  int       W_5_in;
  int       W_6_in;
  int       W_7_in;
//----- -----
 double     X_do_1;
 int        X_in_2;
 double     X_do_3;
 int        X_in_4;
 double     X_do_5;
 int        X_in_6;
 bool       X_bo_7;

 W_4_bo = false ;
 W_5_in=L_42_in_F0 + 1;
 do
 {
   W_3_bo = true ;
   W_4_bo = true ;
   for (W_6_in = W_5_in ; W_6_in >= W_5_in - L_42_in_F0 ; W_6_in --)
   {
     if ( iHigh(L_330_st_2940,S_0_in,W_6_in)>iHigh(L_330_st_2940,S_0_in,W_5_in) )
     {
       W_4_bo = false ;
     }
   }
   for (W_7_in = W_5_in ; W_7_in <= W_5_in + L_41_in_EC ; W_7_in ++)
   {
     if ( iHigh(L_330_st_2940,S_0_in,W_7_in)>iHigh(L_330_st_2940,S_0_in,W_5_in) )
     {
       W_3_bo = false ;
     }
   }
   if ( W_4_bo && W_3_bo && iHigh(L_330_st_2940,S_0_in,W_5_in)>L_48_do_108 * L_201_do_1C98 + MarketInfo(L_330_st_2940,MODE_ASK) )
   {
     X_do_1 = iHigh(L_330_st_2940,S_0_in,W_5_in);
     X_in_2 = W_5_in;
     X_do_3 = iHigh(L_330_st_2940,0,0);
     for (X_in_4 = 1 ; X_in_4 <= X_in_2 ; X_in_4=X_in_4 + 1)
     {
       if ( iHigh(L_330_st_2940,0,X_in_4)>X_do_3 )
       {
         X_do_3 = iHigh(L_330_st_2940,0,X_in_4);
       }
     }
     if ( X_do_1>=X_do_3 )
     {
       X_do_5 = NormalizeDouble(iHigh(L_330_st_2940,S_0_in,W_5_in),L_147_in_3B0);
       X_bo_7=false; 
       for (X_in_6 = OrdersTotal() ; X_in_6 >= 0 ; X_in_6=X_in_6 - 1)
       {
         if ( OrderSelect(X_in_6,0,0) != true || OrderMagicNumber() != L_62_in_160 || OrderSymbol() != L_330_st_2940 || OrderType() != 4 || !(MathAbs(OrderOpenPrice() - (L_52_do_120 * L_201_do_1C98 + X_do_5))<L_56_do_140 * L_201_do_1C98) )   continue;
         X_bo_7 = true;
          break;
         
       }
       if ( !(X_bo_7) && ( !(L_43_bo_F4) || !(iClose(L_330_st_2940,S_0_in,W_5_in - 1)>iHigh(L_330_st_2940,S_0_in,W_5_in) - L_48_do_108 * L_201_do_1C98) ) )
       {
         W_2_bo = true ;
         L_245_do_1D90 = NormalizeDouble(iHigh(L_330_st_2940,S_0_in,W_5_in),L_147_in_3B0) ;
         L_248_in_1DA8 = W_5_in ;
         break;
       }
     }
   }
   W_5_in ++;
   if ( W_5_in <= L_45_in_F8 )   continue;
   L_245_do_1D90 = 0.0 ;
   break;
   
 }
 while(!(W_2_bo));
 
 return(L_245_do_1D90); 
 }
//ccbsw_10 <<==--------   --------
 double ccbsw_11( int S_0_in)
 {
  bool      W_2_bo = false;
  bool      W_3_bo = false;
  bool      W_4_bo;
  int       W_5_in;
  int       W_6_in;
  int       W_7_in;
//----- -----
 double     X_do_1;
 int        X_in_2;
 double     X_do_3;
 int        X_in_4;
 double     X_do_5;
 int        X_in_6;
 bool       X_bo_7;

 W_4_bo = false ;
 W_5_in=L_42_in_F0 + 1;
 do
 {
   W_3_bo = true ;
   W_4_bo = true ;
   for (W_6_in = W_5_in ; W_6_in >= W_5_in - L_42_in_F0 ; W_6_in --)
   {
     if ( iLow(L_330_st_2940,S_0_in,W_6_in)<iLow(L_330_st_2940,S_0_in,W_5_in) )
     {
       W_4_bo = false ;
     }
   }
   for (W_7_in = W_5_in ; W_7_in <= W_5_in + L_41_in_EC ; W_7_in ++)
   {
     if ( iLow(L_330_st_2940,S_0_in,W_7_in)<iLow(L_330_st_2940,S_0_in,W_5_in) )
     {
       W_3_bo = false ;
     }
   }
   if ( W_4_bo && W_3_bo && iLow(L_330_st_2940,S_0_in,W_5_in)<MarketInfo(L_330_st_2940,MODE_BID) - L_48_do_108 * L_201_do_1C98 )
   {
     X_do_1 = iLow(L_330_st_2940,S_0_in,W_5_in);
     X_in_2 = W_5_in;
     X_do_3 = iLow(L_330_st_2940,0,0);
     for (X_in_4 = 1 ; X_in_4 <= X_in_2 ; X_in_4=X_in_4 + 1)
     {
       if ( iLow(L_330_st_2940,0,X_in_4)<X_do_3 )
       {
         X_do_3 = iLow(L_330_st_2940,0,X_in_4);
       }
     }
     if ( X_do_1<=X_do_3 )
     {
       X_do_5 = NormalizeDouble(iLow(L_330_st_2940,S_0_in,W_5_in),L_147_in_3B0);
       X_bo_7=false; 
       for (X_in_6 = OrdersTotal() ; X_in_6 >= 0 ; X_in_6=X_in_6 - 1)
       {
         if ( OrderSelect(X_in_6,0,0) != true || OrderMagicNumber() != L_62_in_160 || OrderSymbol() != L_330_st_2940 || OrderType() != 5 || !(MathAbs(OrderOpenPrice() - (X_do_5 - L_53_do_128 * L_201_do_1C98))<L_56_do_140 * L_201_do_1C98) )   continue;
         X_bo_7 = true;
          break;
         
       }
       if ( !(X_bo_7) && ( !(L_43_bo_F4) || !(iClose(L_330_st_2940,S_0_in,W_5_in - 1)<L_48_do_108 * L_201_do_1C98 + iLow(L_330_st_2940,S_0_in,W_5_in)) ) )
       {
         W_2_bo = true ;
         L_244_do_1D88 = NormalizeDouble(iLow(L_330_st_2940,S_0_in,W_5_in),L_147_in_3B0) ;
         L_249_in_1DAC = W_5_in ;
         break;
       }
     }
   }
   W_5_in ++;
   if ( W_5_in <= L_45_in_F8 )   continue;
   L_244_do_1D88 = 0.0 ;
   break;
   
 }
 while(!(W_2_bo));
 
 return(L_244_do_1D88); 
 }
//ccbsw_11 <<==--------   --------
 double ccbsw_12( int S_0_in,int S_1_in,int S_2_in)
 {
  bool      W_2_bo = false;
  double    W_3_do = 0.0;
  bool      W_4_bo = false;
  bool      W_5_bo;
  int       W_6_in;
  int       W_7_in;
  int       W_8_in;
//----- -----

 W_5_bo = false ;
 W_6_in=S_2_in + 1;
 do
 {
   W_4_bo = true ;
   W_5_bo = true ;
   for (W_7_in = W_6_in ; W_7_in >= W_6_in - S_2_in ; W_7_in --)
   {
     if ( iHigh(L_330_st_2940,S_0_in,W_7_in)>iHigh(L_330_st_2940,S_0_in,W_6_in) )
     {
       W_5_bo = false ;
     }
   }
   for (W_8_in = W_6_in ; W_8_in <= W_6_in + S_1_in ; W_8_in ++)
   {
     if ( iHigh(L_330_st_2940,S_0_in,W_8_in)>iHigh(L_330_st_2940,S_0_in,W_6_in) )
     {
       W_4_bo = false ;
     }
   }
   if ( W_5_bo && W_4_bo && iHigh(L_330_st_2940,S_0_in,W_6_in)>L_189_do_1918 * L_201_do_1C98 + MarketInfo(L_330_st_2940,MODE_ASK) )
   {
     W_2_bo = true ;
     W_3_do = NormalizeDouble(iHigh(L_330_st_2940,S_0_in,W_6_in),L_147_in_3B0) ;
     break;
   }
   W_6_in ++;
   if ( W_6_in <= L_83_in_21C )   continue;
   W_3_do = 9999.0 ;
   break;
   
 }
 while(!(W_2_bo));
 
 return(W_3_do); 
 }
//ccbsw_12 <<==--------   --------
 double ccbsw_13( int S_0_in,int S_1_in,int S_2_in)
 {
  bool      W_2_bo = false;
  double    W_3_do = 0.0;
  bool      W_4_bo = false;
  bool      W_5_bo;
  int       W_6_in;
  int       W_7_in;
  int       W_8_in;
//----- -----

 W_5_bo = false ;
 W_6_in=S_2_in + 1;
 do
 {
   W_4_bo = true ;
   W_5_bo = true ;
   for (W_7_in = W_6_in ; W_7_in >= W_6_in - S_2_in ; W_7_in --)
   {
     if ( iLow(L_330_st_2940,S_0_in,W_7_in)<iLow(L_330_st_2940,S_0_in,W_6_in) )
     {
       W_5_bo = false ;
     }
   }
   for (W_8_in = W_6_in ; W_8_in <= W_6_in + S_1_in ; W_8_in ++)
   {
     if ( iLow(L_330_st_2940,S_0_in,W_8_in)<iLow(L_330_st_2940,S_0_in,W_6_in) )
     {
       W_4_bo = false ;
     }
   }
   if ( W_5_bo && W_4_bo && iLow(L_330_st_2940,S_0_in,W_6_in)<MarketInfo(L_330_st_2940,MODE_BID) - L_189_do_1918 * L_201_do_1C98 )
   {
     W_2_bo = true ;
     W_3_do = NormalizeDouble(iLow(L_330_st_2940,S_0_in,W_6_in),L_147_in_3B0) ;
     break;
   }
   W_6_in ++;
   if ( W_6_in <= L_83_in_21C )   continue;
   W_3_do = 0.0 ;
   break;
   
 }
 while(!(W_2_bo));
 
 return(W_3_do); 
 }
//ccbsw_13 <<==--------   --------
 bool ccbsw_14( int S_0_in)
 {
  bool      W_2_bo;
  double    W_3_do;
  double    W_4_do;
  double    W_5_do;
  double    W_6_do;
//----- -----
 bool       X_bo_1;
 int        X_in_2;
 double     X_do_3;
 int        X_in_4;
 bool       X_bo_5;
 int        X_in_6;
 int        X_in_7;
 double     X_do_8;
 int        X_in_9;
 bool       X_bo_10;
 int        X_in_11;
 bool       X_bo_12;
 int        X_in_13;
 double     X_do_14;
 int        X_in_15;
 int        X_in_16;

 if ( L_186_bo_190C )
 {
   X_bo_1 = false;
 }
 else
 {
   X_bo_1=false; 
   for (X_in_2 = 0 ; X_in_2 < OrdersTotal() ; X_in_2=X_in_2 + 1)
   {
     if ( OrderSelect(X_in_2,0,0) != true || OrderType() != 0 || OrderMagicNumber() != L_62_in_160 || OrderSymbol() != L_330_st_2940 )   continue;
     X_bo_1 = true;
      break;
     
   }
 }
 if ( X_bo_1 == true )
 {
   return(false); 
 }
 if ( L_180_bo_15A8 && L_251_do_1DB8<L_252_do_1DC0 )
 {
   return(false); 
 }
 if ( S_0_in == 1 )
 {
    ccbsw_10(L_39_in_E4);   
   W_2_bo = false ;
   X_do_3 = L_245_do_1D90;
   X_bo_5=false; 
   for (X_in_4 = OrdersTotal() ; X_in_4 >= 0 ; X_in_4=X_in_4 - 1)
   {
     if ( OrderSelect(X_in_4,0,0) != true || OrderMagicNumber() != L_62_in_160 || OrderSymbol() != L_330_st_2940 || OrderType() != 4 || !(MathAbs(OrderOpenPrice() - (L_52_do_120 * L_201_do_1C98 + X_do_3))<L_56_do_140 * L_201_do_1C98) )   continue;
     X_bo_5 = true;
      break;
     
   }
   if ( !(X_bo_5) )
   {
     X_in_6 = 0;
     for (X_in_7 = OrdersTotal() ; X_in_7 >= 0 ; X_in_7=X_in_7 - 1)
     {
       if ( OrderSelect(X_in_7,0,0) != true || OrderMagicNumber() != L_62_in_160 || OrderSymbol() != L_330_st_2940 || OrderType() != 4 )   continue;
       X_in_6=X_in_6 + 1;
       
     }
     if ( X_in_6 == L_55_in_138 )
     {
       X_do_8 = 9999.0;
       for (X_in_9 = OrdersTotal() ; X_in_9 >= 0 ; X_in_9=X_in_9 - 1)
       {
         if ( OrderSelect(X_in_9,0,0) != true || OrderMagicNumber() != L_62_in_160 || OrderSymbol() != L_330_st_2940 || OrderType() != 4 || !(OrderOpenPrice()<X_do_8) )   continue;
         X_do_8 = OrderOpenPrice();
         
       }
       if ( L_245_do_1D90>X_do_8 )
       {
         return(false); 
       }
     }
     L_247_do_1DA0 = L_245_do_1D90 ;
     W_2_bo = true ;
     L_145_do_3A0 = NormalizeDouble(L_245_do_1D90,L_147_in_3B0) ;
   }
   if ( L_145_do_3A0==0.0 )
   {
     return(false); 
   }
   if ( W_2_bo )
   {
     L_228_do_1D10 = L_93_do_268 ;
     W_3_do = NormalizeDouble(L_52_do_120 * L_201_do_1C98 + L_145_do_3A0,L_147_in_3B0) ;
     L_303_do_20B0 = W_3_do ;
     if ( !(L_34_bo_C8) )
     {
       if ( L_36_bo_D0 && AccountFreeMarginCheck(L_330_st_2940,0,L_192_do_195C_si99[L_321_in_2910])<=0.0 )
       {
         Print("Free margin not sufficient for setting order with lotsize " + string(L_192_do_195C_si99[L_321_in_2910]) + "..."); 
         return(false); 
       }
       W_4_do = NormalizeDouble(L_7_in_18 * L_201_do_1C98 + W_3_do,L_147_in_3B0) ;
       W_5_do = NormalizeDouble(W_3_do - (L_69_do_1A0 + L_31_do_B8) * L_201_do_1C98,L_147_in_3B0) ;
       W_6_do = NormalizeDouble(L_70_do_1A8 * L_201_do_1C98 + W_3_do,L_147_in_3B0) ;
       if ( L_192_do_195C_si99[L_321_in_2910]<SymbolInfoDouble(L_330_st_2940,34) )
       {
         Print("Volume is less than the minimal allowed SYMBOL_VOLUME_MIN=" + string(SymbolInfoDouble(L_330_st_2940,34))); 
         X_bo_10 = false;
       }
       else
       {
         if ( L_192_do_195C_si99[L_321_in_2910]>SymbolInfoDouble(L_330_st_2940,35) )
         {
           Print("Volume is greater than the maximal allowed SYMBOL_VOLUME_MAX=" + string(SymbolInfoDouble(L_330_st_2940,35))); 
           X_bo_10 = false;
         }
         else
         {
           if ( MathAbs((int(MathRound(L_192_do_195C_si99[L_321_in_2910] / SymbolInfoDouble(L_330_st_2940,36)))) * SymbolInfoDouble(L_330_st_2940,36) - L_192_do_195C_si99[L_321_in_2910])>0.0000001 )
           {
             Print("Volume is not a multiple of the minimal step SYMBOL_VOLUME_STEP=" + string(SymbolInfoDouble(L_330_st_2940,36))); 
             X_bo_10 = false;
           }
           else
           {
             X_bo_10 = true;
           }
         }
       }

       X_in_11 = AccountInfoInteger(ACCOUNT_LIMIT_ORDERS);
       if ( X_in_11 == 0 )
       {
         X_bo_12 = true;
       }
       else
       {
         X_bo_12 = OrdersTotal()<X_in_11;
       }
       if ( ( !(X_bo_10) || !(X_bo_12) ) )
       {
         return(false); 
       }
       if ( MarketInfo(L_330_st_2940,MODE_ASK)<W_4_do - L_302_do_20A8 * L_201_do_1C98 && MarketInfo(L_330_st_2940,MODE_ASK)<W_4_do - L_189_do_1918 * L_201_do_1C98 )
       {
         if ( !(setSL_TP_After_Entry) )
         {
           L_202_in_1CA0 = OrderSend(L_330_st_2940,4,L_192_do_195C_si99[L_321_in_2910],W_4_do,int(L_15_do_50 * L_201_do_1C98),W_5_do,W_6_do,L_328_st_2930,L_62_in_160,L_294_da_2080,Green) ;
         }
         else
         {
           L_202_in_1CA0 = OrderSend(L_330_st_2940,4,L_192_do_195C_si99[L_321_in_2910],W_4_do,int(L_15_do_50 * L_201_do_1C98),0.0,0.0,L_328_st_2930,L_62_in_160,L_294_da_2080,Green) ;
         }
         L_266_bo_1E0A = false ;
         if ( L_202_in_1CA0 <= 0 )
         {
           X_in_13 = GetLastError();
           if ( X_in_13 == 132 )
           {
             ResetLastError();
             if(1==0) //条件不成立
             {
               do
               {
                 Sleep(2500); 
                 if ( !(setSL_TP_After_Entry) )
                 {
                   X_in_13 = L_15_do_50 * L_201_do_1C98;
                   L_202_in_1CA0 = OrderSend(L_330_st_2940,4,L_192_do_195C_si99[L_321_in_2910],W_4_do,X_in_13,W_5_do,W_6_do,L_328_st_2930,L_62_in_160,L_294_da_2080,Green) ;
                 }
                 else
                 {
                   L_202_in_1CA0 = OrderSend(L_330_st_2940,4,L_192_do_195C_si99[L_321_in_2910],W_4_do,int(L_15_do_50 * L_201_do_1C98),0.0,0.0,L_328_st_2930,L_62_in_160,L_294_da_2080,Green) ;
                 }
                 L_266_bo_1E0A = false ;
               }
               while(GetLastError() == 132);
               
             }
           }
           Print("error: \'" + ccbsw_19(GetLastError()) + "\' when setting entry order"); 
         }
         else
         {
           X_do_14 = W_3_do;
           X_in_15 = L_202_in_1CA0;
           for (X_in_16 = 0 ; X_in_16 < 100 ; X_in_16=X_in_16 + 1)
           {
             if ( !(L_155_do_F08_si100si2[X_in_16][0]==0.0) )   continue;
             L_155_do_F08_si100si2[X_in_16][0] = X_in_15;
             L_155_do_F08_si100si2[X_in_16][1] = X_do_14;
             break;
             
           }
         }
       }
     }
     return(true); 
   }
 }
 return(false); 
 }
//ccbsw_14 <<==--------   --------
 bool ccbsw_15( int S_0_in)
 {
  bool      W_2_bo;
  double    W_3_do;
  double    W_4_do;
  double    W_5_do;
  double    W_6_do;
//----- -----
 bool       X_bo_1;
 int        X_in_2;
 double     X_do_3;
 int        X_in_4;
 bool       X_bo_5;
 int        X_in_6;
 int        X_in_7;
 double     X_do_8;
 int        X_in_9;
 bool       X_bo_10;
 int        X_in_11;
 bool       X_bo_12;
 int        X_in_13;
 double     X_do_14;
 int        X_in_15;
 int        X_in_16;

 if ( L_186_bo_190C )
 {
   X_bo_1 = false;
 }
 else
 {
   X_bo_1=false; 
   for (X_in_2 = 0 ; X_in_2 < OrdersTotal() ; X_in_2=X_in_2 + 1)
   {
     if ( OrderSelect(X_in_2,0,0) != true || OrderType() != 1 || OrderMagicNumber() != L_62_in_160 || OrderSymbol() != L_330_st_2940 )   continue;
     X_bo_1 = true;
      break;
     
   }
 }
 if ( X_bo_1 == true )
 {
   return(false); 
 }
 if ( L_180_bo_15A8 && L_251_do_1DB8>L_252_do_1DC0 )
 {
   return(false); 
 }
 if ( S_0_in == 1 )
 {
   ccbsw_11(L_39_in_E4);
   W_2_bo = false ;
   X_do_3 = L_244_do_1D88;
   X_bo_5=false; 
   for (X_in_4 = OrdersTotal() ; X_in_4 >= 0 ; X_in_4=X_in_4 - 1)
   {
     if ( OrderSelect(X_in_4,0,0) != true || OrderMagicNumber() != L_62_in_160 || OrderSymbol() != L_330_st_2940 || OrderType() != 5 || !(MathAbs(OrderOpenPrice() - (X_do_3 - L_53_do_128 * L_201_do_1C98))<L_56_do_140 * L_201_do_1C98) )   continue;
     X_bo_5 = true;
      break;
     
   }
   if ( !(X_bo_5) )
   {
     X_in_6 = 0;
     for (X_in_7 = OrdersTotal() ; X_in_7 >= 0 ; X_in_7=X_in_7 - 1)
     {
       if ( OrderSelect(X_in_7,0,0) != true || OrderMagicNumber() != L_62_in_160 || OrderSymbol() != L_330_st_2940 || OrderType() != 5 )   continue;
       X_in_6=X_in_6 + 1;
       
     }
     if ( X_in_6 == L_55_in_138 )
     {
       X_do_8 = 0.0;
       for (X_in_9 = OrdersTotal() ; X_in_9 >= 0 ; X_in_9=X_in_9 - 1)
       {
         if ( OrderSelect(X_in_9,0,0) != true || OrderMagicNumber() != L_62_in_160 || OrderSymbol() != L_330_st_2940 || OrderType() != 5 || !(OrderOpenPrice()>X_do_8) )   continue;
         X_do_8 = OrderOpenPrice();
         
       }
       if ( L_244_do_1D88<X_do_8 )
       {
         return(false); 
       }
     }
     L_246_do_1D98 = L_244_do_1D88 ;
     W_2_bo = true ;
     L_146_do_3A8 = NormalizeDouble(L_244_do_1D88,L_147_in_3B0) ;
   }
   if ( L_146_do_3A8==0.0 )
   {
     return(false); 
   }
   if ( W_2_bo )
   {
     L_228_do_1D10 = L_93_do_268 ;
     W_3_do = NormalizeDouble(L_146_do_3A8 - L_53_do_128 * L_201_do_1C98,L_147_in_3B0) ;
     L_304_do_20B8 = W_3_do ;
     if ( !(L_34_bo_C8) )
     {
       if ( L_36_bo_D0 && AccountFreeMarginCheck(L_330_st_2940,1,L_192_do_195C_si99[L_321_in_2910])<=0.0 )
       {
         Print("Free margin not sufficient for setting order with lotsize " + string(L_192_do_195C_si99[L_321_in_2910]) + "..."); 
         return(false); 
       }
       W_4_do = NormalizeDouble(W_3_do - L_7_in_18 * L_201_do_1C98,L_147_in_3B0) ;
       W_5_do = NormalizeDouble((L_69_do_1A0 + L_31_do_B8) * L_201_do_1C98 + W_3_do,L_147_in_3B0) ;
       W_6_do = NormalizeDouble(W_3_do - L_70_do_1A8 * L_201_do_1C98,L_147_in_3B0) ;
       if ( L_192_do_195C_si99[L_321_in_2910]<SymbolInfoDouble(L_330_st_2940,34) )
       {
         Print("Volume is less than the minimal allowed SYMBOL_VOLUME_MIN=" + string(SymbolInfoDouble(L_330_st_2940,34))); 
         X_bo_10 = false;
       }
       else
       {
         if ( L_192_do_195C_si99[L_321_in_2910]>SymbolInfoDouble(L_330_st_2940,35) )
         {
           Print("Volume is greater than the maximal allowed SYMBOL_VOLUME_MAX=" + string(SymbolInfoDouble(L_330_st_2940,35))); 
           X_bo_10 = false;
         }
         else
         {
           if ( MathAbs((int(MathRound(L_192_do_195C_si99[L_321_in_2910] / SymbolInfoDouble(L_330_st_2940,36)))) * SymbolInfoDouble(L_330_st_2940,36) - L_192_do_195C_si99[L_321_in_2910])>0.0000001 )
           {
             Print("Volume is not a multiple of the minimal step SYMBOL_VOLUME_STEP=" + string(SymbolInfoDouble(L_330_st_2940,36))); 
             X_bo_10 = false;
           }
           else
           {
             X_bo_10 = true;
           }
         }
       }

       X_in_11 = AccountInfoInteger(ACCOUNT_LIMIT_ORDERS);
       if ( X_in_11 == 0 )
       {
         X_bo_12 = true;
       }
       else
       {
         X_bo_12 = OrdersTotal()<X_in_11;
       }
       if ( ( !(X_bo_10) || !(X_bo_12) ) )
       {
         return(false); 
       }
       if ( MarketInfo(L_330_st_2940,MODE_BID)>L_302_do_20A8 * L_201_do_1C98 + W_4_do && MarketInfo(L_330_st_2940,MODE_BID)>L_189_do_1918 * L_201_do_1C98 + W_4_do )
       {
         if ( !(setSL_TP_After_Entry) )
         {
           L_202_in_1CA0 = OrderSend(L_330_st_2940,5,L_192_do_195C_si99[L_321_in_2910],W_4_do,int(L_15_do_50 * L_201_do_1C98),W_5_do,W_6_do,L_328_st_2930,L_62_in_160,L_294_da_2080,Red) ;
         }
         else
         {
           L_202_in_1CA0 = OrderSend(L_330_st_2940,5,L_192_do_195C_si99[L_321_in_2910],W_4_do,int(L_15_do_50 * L_201_do_1C98),0.0,0.0,L_328_st_2930,L_62_in_160,L_294_da_2080,Red) ;
         }
         L_267_bo_1E0B = false ;
         if ( L_202_in_1CA0 <= 0 )
         {
           X_in_13 = GetLastError();
           if ( X_in_13 == 132 )
           {
             ResetLastError();
             if(1==0) //条件不成立
             {
               do
               {
                 Sleep(2500); 
                 if ( !(setSL_TP_After_Entry) )
                 {
                   X_in_13 = L_15_do_50 * L_201_do_1C98;
                   L_202_in_1CA0 = OrderSend(L_330_st_2940,5,L_192_do_195C_si99[L_321_in_2910],W_4_do,X_in_13,W_5_do,W_6_do,L_328_st_2930,L_62_in_160,L_294_da_2080,Red) ;
                 }
                 else
                 {
                   L_202_in_1CA0 = OrderSend(L_330_st_2940,5,L_192_do_195C_si99[L_321_in_2910],W_4_do,int(L_15_do_50 * L_201_do_1C98),0.0,0.0,L_328_st_2930,L_62_in_160,L_294_da_2080,Red) ;
                 }
                 L_267_bo_1E0B = false ;
               }
               while(GetLastError() == 132);
               
             }
           }
           Print("error: \'" + ccbsw_19(GetLastError()) + "\' when setting entry order"); 
         }
         else
         {
           X_do_14 = W_3_do;
           X_in_15 = L_202_in_1CA0;
           for (X_in_16 = 0 ; X_in_16 < 100 ; X_in_16=X_in_16 + 1)
           {
             if ( !(L_155_do_F08_si100si2[X_in_16][0]==0.0) )   continue;
             L_155_do_F08_si100si2[X_in_16][0] = X_in_15;
             L_155_do_F08_si100si2[X_in_16][1] = X_do_14;
             break;
             
           }
         }
       }
     }
   }
 }
 return(false); 
 }
//ccbsw_15 <<==--------   --------
 bool ccbsw_16()
 {
  bool      W_2_bo = false;
  bool      W_3_bo = false;
  double    W_4_do;
  double    W_5_do;
  int       W_6_in;
  double    W_7_do;
  double    W_8_do;
  double    W_9_do;
  double    W_10_do;
  string    W_11_st;
  double    W_12_do;
  datetime  W_13_da;
  int       W_14_in;
  int       W_15_in;
  string    W_16_st;
  double    W_17_do;
  double    W_18_do;
  bool      W_19_bo;
  bool      W_20_bo;
  double    W_21_do;
  bool      W_22_bo;
  double    W_23_do;
  double    W_24_do;
  double    W_25_do;
  double    W_26_do;
  int       W_27_in;
  double    W_28_do;
//----- -----
 int        X_in_1;
 int        X_in_2;
 int        X_in_3;
 double     X_do_4;
 double     X_do_5;
 int        X_in_6;
 int        X_in_7;
 int        X_in_8;
 int        X_in_9;
 int        X_in_10;
 string     X_st_11;
 double     X_do_12;
 int        X_in_13;
 int        X_in_14;
 double     X_do_15;
 int        X_in_16;
 int        X_in_17;
 int        X_in_18;
 int        X_in_19;
 int        X_in_20;
 string     X_st_21;
 int        X_in_22;
 double     X_do_23;
 double     X_do_24;
 int        X_in_25;
 double     X_do_26;
 bool       X_bo_27;
 int        X_in_28;
 int        X_in_29;
 double     X_do_30;
 int        X_in_31;
 int        X_in_32;
 int        X_in_33;
 double     X_do_34;
 double     X_do_35;
 int        X_in_36;
 double     X_do_37;
 bool       X_bo_38;
 int        X_in_39;
 int        X_in_40;
 double     X_do_41;
 int        X_in_42;
 int        X_in_43;

 W_4_do = 0.0 ;
 W_5_do = 0.0 ;
 for (W_6_in = 0 ; W_6_in < OrdersTotal() ; W_6_in ++)
 {
   if ( OrderSelect(W_6_in,0,0) == true )
   {
     W_2_bo = false ;
     W_7_do = NormalizeDouble(OrderStopLoss(),L_147_in_3B0) ;
     W_8_do = NormalizeDouble(OrderTakeProfit(),L_147_in_3B0) ;
     W_9_do = OrderTicket() ;
     W_10_do = NormalizeDouble(OrderOpenPrice(),L_147_in_3B0) ;
     W_11_st = OrderComment() ;
     W_12_do = OrderLots() ;
     W_13_da = OrderOpenTime() ;
     W_14_in = OrderType() ;
     W_15_in = OrderMagicNumber() ;
     W_16_st = OrderSymbol() ;
     if ( ( W_14_in == 4 || W_14_in == 2 ) && L_37_in_D4 == 2 && ( L_64_in_174 == 0 || (L_64_in_174 == 1 && W_16_st == L_330_st_2940) ) && ( W_15_in == L_65_in_178 || L_65_in_178 == 0 ) && ( W_11_st == L_66_st_180 || L_66_st_180 == "" ) )
     {
       if ( ( W_7_do==0.0 || W_7_do==0.0 ) )
       {
         W_7_do = NormalizeDouble(W_10_do - L_69_do_1A0 * L_201_do_1C98,L_147_in_3B0) ;
         OrderModify(W_9_do,W_10_do,W_7_do,W_8_do,0,Green); 
       }
       if ( ( W_8_do==0.0 || W_8_do==0.0 ) )
       {
         W_8_do = NormalizeDouble(L_70_do_1A8 * L_201_do_1C98 + W_10_do,L_147_in_3B0) ;
         OrderModify(W_9_do,W_10_do,W_7_do,W_8_do,0,Green); 
       }
     }
     if ( W_14_in == 0 && ( ( W_15_in == L_62_in_160 && L_37_in_D4 == 1 && W_16_st == L_330_st_2940 ) || (L_37_in_D4 == 2 && ( L_64_in_174 == 0 || (L_64_in_174 == 1 && W_16_st == L_330_st_2940) ) && ( W_15_in == L_65_in_178 || L_65_in_178 == 0 ) && (W_11_st == L_66_st_180 || L_66_st_180 == "")) ) )
     {
       if ( ( W_7_do==0.0 || W_7_do==0.0 ) )
       {
         W_7_do = NormalizeDouble(W_10_do - L_69_do_1A0 * L_201_do_1C98,L_147_in_3B0) ;
         OrderModify(W_9_do,W_10_do,W_7_do,W_8_do,0,Green); 
       }
       if ( ( W_8_do==0.0 || W_8_do==0.0 ) )
       {
         W_8_do = NormalizeDouble(L_70_do_1A8 * L_201_do_1C98 + W_10_do,L_147_in_3B0) ;
         OrderModify(W_9_do,W_10_do,W_7_do,W_8_do,0,Green); 
       }
       L_228_do_1D10 = L_93_do_268 ;
       if ( L_97_in_288 >  0 && TimeCurrent() >  W_13_da + L_97_in_288 * 60 )
       {
         L_228_do_1D10 = L_98_do_290 ;
       }
       X_in_1 = L_147_in_3B0;
       X_in_2 = W_9_do;
       for (X_in_3 = 0 ; X_in_3 < 100 ; X_in_3=X_in_3 + 1)
       {
         if ( !(L_155_do_F08_si100si2[X_in_3][0]==X_in_2) )   continue;
         X_do_4 = L_155_do_F08_si100si2[X_in_3][1];
         break;
         
       }
       X_do_4 = 0.0;
       W_17_do = NormalizeDouble(X_do_4,X_in_1) ;
       if ( W_17_do==0.0 )
       {
         X_do_5 = W_10_do;
         X_in_6 = W_9_do;
         for (X_in_7 = 0 ; X_in_7 < 100 ; X_in_7=X_in_7 + 1)
         {
           if ( !(L_155_do_F08_si100si2[X_in_7][0]==0.0) )   continue;
           L_155_do_F08_si100si2[X_in_7][0] = X_in_6;
           L_155_do_F08_si100si2[X_in_7][1] = X_do_5;
           break;
           
         }
         W_17_do = W_10_do ;
       }
       else
       {
         W_17_do = W_17_do - L_54_do_130 * L_201_do_1C98 ;
       }
       W_18_do = W_10_do - W_17_do ;
       W_19_bo = false ;
       if ( W_17_do>0.0 - L_54_do_130 * L_201_do_1C98 && W_18_do>L_15_do_50 * L_201_do_1C98 )
       {
         W_19_bo = true ;
         if ( L_16_in_58 == 2 )
         {
           L_228_do_1D10 = -1000.0 ;
           Print("SlippageMode 2 active"); 
         }
       }
       if ( L_20_bo_78 )
       {
         W_5_do = W_17_do ;
       }
       else
       {
         W_5_do = W_10_do ;
       }
       if ( W_7_do<NormalizeDouble(W_10_do - (L_69_do_1A0 + L_31_do_B8) * L_201_do_1C98 - L_1_do_0,L_147_in_3B0) )
       {
         W_7_do = NormalizeDouble(W_10_do - (L_69_do_1A0 + L_31_do_B8) * L_201_do_1C98 - L_1_do_0,L_147_in_3B0) ;
         OrderModify(W_9_do,W_10_do,W_7_do,W_8_do,0,0xFFFFFFFF); 
       }
       if ( MarketInfo(L_330_st_2940,MODE_BID)<W_10_do - (L_69_do_1A0 + L_31_do_B8) * L_201_do_1C98 - L_1_do_0 )
       {
         RefreshRates(); 
         OrderClose(OrderTicket(),OrderLots(),MarketInfo(L_330_st_2940,MODE_BID),L_1_do_0,Red); 
         return(true); 
       }
       W_20_bo = false ;
       if ( L_115_bo_2FC )
       {
         X_in_8 = W_9_do;
         X_in_9 = 0;
         for (X_in_10 = OrdersTotal() ; X_in_10 >= 0 ; X_in_10=X_in_10 - 1)
         {
           if ( OrderSelect(X_in_10,0,0) != true || OrderMagicNumber() != L_125_in_340 || OrderSymbol() != L_330_st_2940 )   continue;
           X_st_11 = OrderComment();
           if ( X_st_11 != IntegerToString(X_in_8,0,32) )   continue;
           X_in_9=X_in_9 + 1;
           
         }
         W_21_do = X_in_9 ;
         W_22_bo = false ;
         if ( !(L_151_bo_3C8) )
         {
           L_151_bo_3C8 = true ;
           L_149_in_3C0 = 0 ;
         }
         if ( W_21_do==0.0 )
         {
           L_149_in_3C0 = 0 ;
         }
         if ( MathFloor(W_21_do / 2.0)==W_21_do / 2.0 )
         {
           L_149_in_3C0 = 0 ;
         }
         else
         {
           L_149_in_3C0 = 1 ;
         }
         if ( L_151_bo_3C8 )
         {
           if ( W_21_do>0.0 )
           {
             X_do_12 = AccountEquity();
             if ( X_do_12>AccountBalance() + L_119_do_318 )
             {
               for (X_in_13 = OrdersTotal() ; X_in_13 >= 0 ; X_in_13=X_in_13 - 1)
               {
                 if ( OrderSelect(X_in_13,0,0) != true )   continue;
                 
                 if ( ( OrderMagicNumber() != L_62_in_160 && OrderMagicNumber() != L_126_in_344 && OrderMagicNumber() != L_125_in_340 ) )   continue;
                 
                 if ( OrderType() == 0 )
                 {
                   OrderClose(OrderTicket(),OrderLots(),MarketInfo(L_330_st_2940,MODE_BID),L_15_do_50,Red); 
                 }
                 if ( OrderType() != 1 )   continue;
                 OrderClose(OrderTicket(),OrderLots(),MarketInfo(L_330_st_2940,MODE_ASK),L_15_do_50,Red); 
                 
               }
             }
           }
           if ( W_21_do>0.0 )
           {
             X_in_14 = W_9_do;
             X_do_15 = 0.0;
             for (X_in_16 = OrdersTotal() ; X_in_16 >= 0 ; X_in_16=X_in_16 - 1)
             {
               if ( OrderSelect(X_in_16,0,0) != true )   continue;
               
               if ( OrderTicket() != X_in_14 )
               {
                 X_st_11 = OrderComment();
               if ( X_st_11 != IntegerToString(X_in_14,0,32) )   continue;
               }
               X_do_15 = X_do_15 + OrderProfit();
               
             }
             if ( X_do_15>L_119_do_318 )
             {
               Print("Closing zone"); 
               X_in_17 = W_9_do;
               for (X_in_18 = OrdersTotal() ; X_in_18 >= 0 ; X_in_18=X_in_18 - 1)
               {
                 if ( OrderSelect(X_in_18,0,0) != true )   continue;
                 
                 if ( OrderMagicNumber() == L_62_in_160 && OrderTicket() == X_in_17 )
                 {
                   OrderClose(OrderTicket(),OrderLots(),MarketInfo(L_330_st_2940,MODE_BID),3,Red); 
                 }
                 if ( OrderMagicNumber() != L_125_in_340 )   continue;
                 X_st_11 = OrderComment();
                 if ( X_st_11 != IntegerToString(X_in_17,0,32) )   continue;
                 
                 if ( OrderType() == 0 )
                 {
                   OrderClose(OrderTicket(),OrderLots(),MarketInfo(L_330_st_2940,MODE_BID),L_15_do_50,Red); 
                 }
                 if ( OrderType() != 1 )   continue;
                 OrderClose(OrderTicket(),OrderLots(),MarketInfo(L_330_st_2940,MODE_ASK),L_15_do_50,Red); 
                 
               }
               L_151_bo_3C8 = false ;
               W_20_bo = true ;
             }
           }
           else
           {
             W_23_do = W_12_do * L_121_do_328 ;
             if ( L_120_in_320 == 2 )
             {
               W_23_do = (W_21_do + 1.0) * W_12_do + W_12_do ;
             }
             if ( L_120_in_320 == 3 )
             {
               W_23_do = W_12_do * (MathPow(L_121_do_328,W_21_do + 1.0)) ;
             }
             if ( L_149_in_3C0 == 0 )
             {
               W_24_do = W_21_do * L_117_do_308 * L_201_do_1C98 + (W_17_do - L_116_do_300 * L_201_do_1C98) ;
               if ( W_24_do>W_17_do - L_118_do_310 * L_201_do_1C98 )
               {
                 W_24_do = W_17_do - L_118_do_310 * L_201_do_1C98 ;
               }
               if ( MarketInfo(L_330_st_2940,MODE_BID)<W_24_do )
               {
                 if ( W_21_do>=L_122_in_330 )
                 {
                   for (X_in_19 = OrdersTotal() ; X_in_19 >= 0 ; X_in_19=X_in_19 - 1)
                   {
                     if ( OrderSelect(X_in_19,0,0) != true )   continue;
                     
                     if ( OrderMagicNumber() == L_62_in_160 && OrderTicket() == W_9_do )
                     {
                       OrderClose(OrderTicket(),OrderLots(),MarketInfo(L_330_st_2940,MODE_BID),3,Red); 
                     }
                     if ( OrderMagicNumber() != L_125_in_340 )   continue;
                     X_st_11 = OrderComment();
                     if ( X_st_11 != IntegerToString(W_9_do,0,32) )   continue;
                     
                     if ( OrderType() == 0 )
                     {
                       OrderClose(OrderTicket(),OrderLots(),MarketInfo(L_330_st_2940,MODE_BID),L_15_do_50,Red); 
                     }
                     if ( OrderType() != 1 )   continue;
                     OrderClose(OrderTicket(),OrderLots(),MarketInfo(L_330_st_2940,MODE_ASK),L_15_do_50,Red); 
                     
                   }
                 }
                 else
                 {
                   OrderSend(L_330_st_2940,1,W_23_do,MarketInfo(L_330_st_2940,MODE_BID),L_15_do_50,0.0,0.0,IntegerToString(W_9_do,0,32),L_125_in_340,0,Green); 
                   L_149_in_3C0 = 1 ;
                   W_22_bo = true ;
                 }
               }
             }
             else
             {
               W_25_do = W_17_do ;
               if ( MarketInfo(L_330_st_2940,MODE_ASK)>W_17_do )
               {
                 if ( W_21_do>=L_122_in_330 )
                 {
                   for (X_in_20 = OrdersTotal() ; X_in_20 >= 0 ; X_in_20=X_in_20 - 1)
                   {
                     if ( OrderSelect(X_in_20,0,0) != true )   continue;
                     
                     if ( OrderMagicNumber() == L_62_in_160 && OrderTicket() == W_9_do )
                     {
                       OrderClose(OrderTicket(),OrderLots(),MarketInfo(L_330_st_2940,MODE_BID),3,Red); 
                     }
                     if ( OrderMagicNumber() != L_125_in_340 )   continue;
                     X_st_21 = OrderComment();
                     if ( X_st_21 != IntegerToString(W_9_do,0,32) )   continue;
                     
                     if ( OrderType() == 0 )
                     {
                       OrderClose(OrderTicket(),OrderLots(),MarketInfo(L_330_st_2940,MODE_BID),L_15_do_50,Red); 
                     }
                     if ( OrderType() != 1 )   continue;
                     OrderClose(OrderTicket(),OrderLots(),MarketInfo(L_330_st_2940,MODE_ASK),L_15_do_50,Red); 
                     
                   }
                 }
                 else
                 {
                   OrderSend(L_330_st_2940,0,W_23_do,MarketInfo(L_330_st_2940,MODE_ASK),L_15_do_50,0.0,0.0,IntegerToString(W_9_do,0,32),L_125_in_340,0,Green); 
                   L_149_in_3C0 = 0 ;
                   W_22_bo = true ;
                 }
               }
             }
           }
         }
         if ( ( W_21_do>0.0 || W_22_bo ) )
         {
           W_20_bo = true ;
         }
       }
       if ( !(W_20_bo) )
       {
         if ( ( L_30_in_B0 == 1 || (L_30_in_B0 != 3 && L_30_in_B0 != 2) ) )
         {
           X_in_22 = W_9_do;
           X_do_23 = L_69_do_1A0;
           X_do_24 = W_10_do;
           X_in_25 = 1;
           X_do_26 = 0.0;
           X_bo_27 = false;
           for (X_in_28 = 0 ; X_in_28 < L_156_in_1548 ; X_in_28=X_in_28 + 1)
           {
             if ( L_153_do_400_si20si2[X_in_28][0]==X_in_22 )
             {
               X_do_26 = L_153_do_400_si20si2[X_in_28][1];
               X_bo_27 = true;
               break;
             }
           }
           if ( !(X_bo_27) )
           {
             if ( X_in_25 == 1 )
             {
               X_do_26 = NormalizeDouble(X_do_24 - X_do_23 * L_201_do_1C98,L_147_in_3B0);
             }
             if ( X_in_25 == 2 )
             {
               X_do_26 = NormalizeDouble(X_do_23 * L_201_do_1C98 + X_do_24,L_147_in_3B0);
             }
             for (X_in_29 = 0 ; X_in_29 < L_156_in_1548 ; X_in_29=X_in_29 + 1)
             {
               if ( L_153_do_400_si20si2[X_in_29][0]==0.0 )
               {
                 L_153_do_400_si20si2[X_in_29][0] = X_in_22;
                 L_153_do_400_si20si2[X_in_29][1] = X_do_26;
                 break;
               }
             }
           }
           L_148_do_3B8 = X_do_26 ;
           W_4_do = L_148_do_3B8 ;
           if ( MarketInfo(L_330_st_2940,MODE_BID)<W_4_do )
           {
             Print("Closing with virtual SL"); 
             RefreshRates(); 
             OrderClose(W_9_do,W_12_do,MarketInfo(L_330_st_2940,MODE_BID),L_1_do_0,0xFFFFFFFF); 
             return(true); 
           }
           if ( L_89_do_248>0.0 && TimeCurrent() >= W_13_da + L_296_in_208C && MarketInfo(L_330_st_2940,MODE_BID)>NormalizeDouble(L_90_do_250 * L_201_do_1C98 + (W_7_do + L_331_do_2950),L_147_in_3B0) && MarketInfo(L_330_st_2940,MODE_BID)<W_8_do - L_302_do_20A8 )
           {
             W_7_do = NormalizeDouble(MarketInfo(L_330_st_2940,MODE_BID) - L_90_do_250 * L_201_do_1C98,L_147_in_3B0) ;
             if ( W_7_do<MarketInfo(L_330_st_2940,MODE_BID) - L_189_do_1918 )
             {
               L_202_in_1CA0 = OrderModify(W_9_do,W_10_do,W_7_do,W_8_do,0,0xFFFFFFFF) ;
               if ( L_202_in_1CA0 <= 0 )
               {
                 Print("TrailStop error: \'" + ccbsw_19(GetLastError()) + "\' when setting trailing Exit_TrailSL_after_X_Minutes_size loss.  Trying again!"); 
               }
               W_2_bo = true ;
             }
           }
           if ( L_72_do_1C0>0.0 && MarketInfo(L_330_st_2940,MODE_BID)>NormalizeDouble((L_72_do_1C0 + L_75_do_1D8) * L_201_do_1C98 + (W_7_do + L_331_do_2950),L_147_in_3B0) && MarketInfo(L_330_st_2940,MODE_BID)>NormalizeDouble(L_73_do_1C8 * L_201_do_1C98 + W_5_do,L_147_in_3B0) && MarketInfo(L_330_st_2940,MODE_BID)<W_8_do - L_302_do_20A8 && W_7_do<NormalizeDouble(L_74_do_1D0 * L_201_do_1C98 + W_10_do,L_147_in_3B0) )
           {
             W_7_do = NormalizeDouble(MarketInfo(L_330_st_2940,MODE_BID) - L_72_do_1C0 * L_201_do_1C98,L_147_in_3B0) ;
             if ( W_7_do<MarketInfo(L_330_st_2940,MODE_BID) - L_189_do_1918 )
             {
               L_202_in_1CA0 = OrderModify(W_9_do,W_10_do,W_7_do,W_8_do,0,0xFFFFFFFF) ;
               if ( L_202_in_1CA0 <= 0 )
               {
                 Print("TrailStop error: \'" + ccbsw_19(GetLastError()) + "\' when setting trailing Exit_stop loss.  Trying again!"); 
               }
               else
               {
                 W_26_do = NormalizeDouble(L_76_do_1E0 / 100.0 * L_192_do_195C_si99[L_321_in_2910],2) ;
                 if ( W_26_do<W_12_do && W_26_do>=MarketInfo(L_330_st_2940,MODE_LOTSTEP) )
                 {
                   OrderClose(W_9_do,W_26_do,MarketInfo(L_330_st_2940,MODE_BID),L_15_do_50,Red); 
                   return(true); 
                 }
               }
               W_2_bo = true ;
             }
           }
           if ( W_19_bo && L_16_in_58 == 1 && L_18_do_68>0.0 && MarketInfo(L_330_st_2940,MODE_BID)>NormalizeDouble(L_18_do_68 * L_201_do_1C98 + (W_7_do + L_331_do_2950),L_147_in_3B0) && MarketInfo(L_330_st_2940,MODE_BID)>NormalizeDouble(L_17_do_60 * L_201_do_1C98 + W_17_do,L_147_in_3B0) && MarketInfo(L_330_st_2940,MODE_BID)<W_8_do - L_302_do_20A8 && W_7_do<NormalizeDouble(L_19_do_70 * L_201_do_1C98 + W_10_do,L_147_in_3B0) )
           {
             W_7_do = NormalizeDouble(MarketInfo(L_330_st_2940,MODE_BID) - L_18_do_68 * L_201_do_1C98,L_147_in_3B0) ;
             if ( W_7_do<MarketInfo(L_330_st_2940,MODE_BID) - L_189_do_1918 )
             {
               L_202_in_1CA0 = OrderModify(W_9_do,W_10_do,W_7_do,W_8_do,0,0xFFFFFFFF) ;
               if ( L_202_in_1CA0 <= 0 )
               {
                 Print("TrailStop error: \'" + ccbsw_19(GetLastError()) + "\' when setting Slip TL.  Trying again!"); 
               }
               else
               {
                 Print("Slippage control active"); 
               }
               W_2_bo = true ;
             }
           }
           if ( L_84_in_220 >  0 && L_85_in_224 >= 0 && L_219_do_1CE8>NormalizeDouble(W_7_do + L_189_do_1918 + L_331_do_2950,L_147_in_3B0) && ( L_219_do_1CE8<W_10_do || !(L_81_bo_214) ) && L_219_do_1CE8<NormalizeDouble(MarketInfo(L_330_st_2940,MODE_BID) - L_86_in_228 * L_201_do_1C98 - L_189_do_1918 - L_331_do_2950,L_147_in_3B0) && MarketInfo(L_330_st_2940,MODE_BID)<W_8_do - L_302_do_20A8 )
           {
             W_7_do = NormalizeDouble(L_219_do_1CE8,L_147_in_3B0) ;
             if ( W_7_do<MarketInfo(L_330_st_2940,MODE_BID) - L_189_do_1918 )
             {
               L_202_in_1CA0 = OrderModify(W_9_do,W_10_do,W_7_do,W_8_do,0,0xFFFFFFFF) ;
               if ( L_202_in_1CA0 <= 0 )
               {
                 Print("error: \'" + ccbsw_19(GetLastError()) + "\' when modifying stoploss"); 
               }
               W_2_bo = true ;
             }
           }
           if ( L_78_do_1F8>0.0 && MarketInfo(L_330_st_2940,MODE_BID)>NormalizeDouble(L_78_do_1F8 * L_201_do_1C98 + W_10_do,L_147_in_3B0) && NormalizeDouble(L_79_do_200 * L_201_do_1C98 + W_10_do,L_147_in_3B0)>W_7_do + L_331_do_2950 && MarketInfo(L_330_st_2940,MODE_BID)>NormalizeDouble(L_79_do_200 * L_201_do_1C98 + W_10_do + L_189_do_1918,L_147_in_3B0) && MarketInfo(L_330_st_2940,MODE_BID)<W_8_do - L_302_do_20A8 )
           {
             W_7_do = NormalizeDouble(L_79_do_200 * L_201_do_1C98 + W_10_do,L_147_in_3B0) ;
             if ( W_7_do<MarketInfo(L_330_st_2940,MODE_BID) - L_189_do_1918 )
             {
               L_202_in_1CA0 = OrderModify(W_9_do,W_10_do,W_7_do,W_8_do,0,0xFFFFFFFF) ;
               if ( L_202_in_1CA0 <= 0 )
               {
                 Print("error when setting breakeven: \'" + ccbsw_19(GetLastError()) + "\' ..\'Exit_BE_start\' to close to \'Exit_BE_extra_pips\' ..trying again!"); 
               }
               W_2_bo = true ;
             }
           }
           if ( !(W_2_bo) && ( L_92_in_264 == 1 || (L_92_in_264 == 2 && L_95_do_278 * L_201_do_1C98 + W_7_do<=L_96_do_280 * L_201_do_1C98 + (W_5_do + L_1_do_0)) ) )
           {
             L_233_in_1D28 ++;
             if ( MarketInfo(L_330_st_2940,MODE_BID)>L_95_do_278 * L_201_do_1C98 + W_7_do + L_189_do_1918 && MarketInfo(L_330_st_2940,MODE_BID)<W_8_do - L_302_do_20A8 && ( L_93_do_268==0.0 || MarketInfo(L_330_st_2940,MODE_BID)>L_228_do_1D10 * L_201_do_1C98 + W_5_do ) && L_233_in_1D28 >= L_94_in_270 && NormalizeDouble(L_95_do_278 * L_201_do_1C98 + W_7_do,L_147_in_3B0)>W_7_do )
             {
               L_233_in_1D28 = 0 ;
               W_7_do = NormalizeDouble(L_95_do_278 * L_201_do_1C98 + W_7_do,L_147_in_3B0) ;
               OrderModify(W_9_do,W_10_do,W_7_do,W_8_do,0,0xFFFFFFFF); 
               W_2_bo = true ;
             }
           }
           L_148_do_3B8 = W_7_do ;
           if ( MarketInfo(L_330_st_2940,MODE_BID)<W_7_do )
           {
             Print("Closing with virtual SL"); 
             RefreshRates(); 
             OrderClose(W_9_do,W_12_do,MarketInfo(L_330_st_2940,MODE_BID),L_1_do_0,0xFFFFFFFF); 
             return(true); 
           }
           if ( NormalizeDouble(W_4_do,L_147_in_3B0)!=NormalizeDouble(L_148_do_3B8,L_147_in_3B0) )
           {
             X_do_30 = NormalizeDouble(L_148_do_3B8,L_147_in_3B0);
             X_in_31 = W_9_do;
             for (X_in_32 = 0 ; X_in_32 < L_156_in_1548 ; X_in_32=X_in_32 + 1)
             {
               if ( L_153_do_400_si20si2[X_in_32][0]==X_in_31 )
               {
                 L_153_do_400_si20si2[X_in_32][1] = X_do_30;
                 break;
               }
             }
           }
           if ( W_2_bo && L_99_bo_298 )
           {
             return(true); 
           }
         }
         if ( ( L_30_in_B0 == 2 || L_30_in_B0 == 3 ) )
         {
           X_in_33 = W_9_do;
           X_do_34 = L_69_do_1A0;
           X_do_35 = W_10_do;
           X_in_36 = 1;
           X_do_37 = 0.0;
           X_bo_38 = false;
           for (X_in_39 = 0 ; X_in_39 < L_156_in_1548 ; X_in_39=X_in_39 + 1)
           {
             if ( L_153_do_400_si20si2[X_in_39][0]==X_in_33 )
             {
               X_do_37 = L_153_do_400_si20si2[X_in_39][1];
               X_bo_38 = true;
               break;
             }
           }
           if ( !(X_bo_38) )
           {
             if ( X_in_36 == 1 )
             {
               X_do_37 = NormalizeDouble(X_do_35 - X_do_34 * L_201_do_1C98,L_147_in_3B0);
             }
             if ( X_in_36 == 2 )
             {
               X_do_37 = NormalizeDouble(X_do_34 * L_201_do_1C98 + X_do_35,L_147_in_3B0);
             }
             for (X_in_40 = 0 ; X_in_40 < L_156_in_1548 ; X_in_40=X_in_40 + 1)
             {
               if ( L_153_do_400_si20si2[X_in_40][0]==0.0 )
               {
                 L_153_do_400_si20si2[X_in_40][0] = X_in_33;
                 L_153_do_400_si20si2[X_in_40][1] = X_do_37;
                 break;
               }
             }
           }
           L_148_do_3B8 = X_do_37 ;
           W_4_do = L_148_do_3B8 ;
           if ( MarketInfo(L_330_st_2940,MODE_BID)<=W_4_do )
           {
             RefreshRates(); 
             OrderClose(W_9_do,W_12_do,MarketInfo(L_330_st_2940,MODE_BID),L_1_do_0,0xFFFFFFFF); 
             return(true); 
           }
           W_27_in = TimeCurrent() - L_312_da_20F0 ;
           if ( W_27_in >= L_32_in_C0 )
           {
             if ( NormalizeDouble(L_148_do_3B8,L_147_in_3B0)>W_7_do + L_331_do_2950 )
             {
               OrderModify(W_9_do,W_10_do,NormalizeDouble(L_148_do_3B8,L_147_in_3B0),W_8_do,0,0xFFFFFFFF); 
             }
             L_312_da_20F0 = TimeCurrent() ;
           }
           if ( L_89_do_248>0.0 && TimeCurrent() >= W_13_da + L_296_in_208C && MarketInfo(L_330_st_2940,MODE_BID)>L_90_do_250 * L_201_do_1C98 + (L_148_do_3B8 + L_331_do_2950) && MarketInfo(L_330_st_2940,MODE_BID)<W_8_do - L_302_do_20A8 )
           {
             W_2_bo = true ;
             L_148_do_3B8 = MarketInfo(L_330_st_2940,MODE_BID) - L_90_do_250 * L_201_do_1C98 ;
           }
           if ( L_72_do_1C0>0.0 && MarketInfo(L_330_st_2940,MODE_BID)>(L_72_do_1C0 + L_75_do_1D8) * L_201_do_1C98 + (L_148_do_3B8 + L_331_do_2950) && MarketInfo(L_330_st_2940,MODE_BID)>L_73_do_1C8 * L_201_do_1C98 + W_5_do && L_148_do_3B8<L_74_do_1D0 * L_201_do_1C98 + W_10_do )
           {
             W_2_bo = true ;
             L_148_do_3B8 = MarketInfo(L_330_st_2940,MODE_BID) - L_72_do_1C0 * L_201_do_1C98 ;
             W_28_do = NormalizeDouble(L_76_do_1E0 / 100.0 * L_192_do_195C_si99[L_321_in_2910],2) ;
             if ( W_28_do<W_12_do && W_28_do>=MarketInfo(L_330_st_2940,MODE_LOTSTEP) )
             {
               OrderClose(W_9_do,W_28_do,MarketInfo(L_330_st_2940,MODE_BID),L_15_do_50,Red); 
               return(true); 
             }
           }
           if ( W_19_bo && L_16_in_58 == 1 && L_18_do_68>0.0 && MarketInfo(L_330_st_2940,MODE_BID)>L_18_do_68 * L_201_do_1C98 + (L_148_do_3B8 + L_331_do_2950) && MarketInfo(L_330_st_2940,MODE_BID)>L_17_do_60 * L_201_do_1C98 + W_17_do && MarketInfo(L_330_st_2940,MODE_BID)<W_8_do - L_302_do_20A8 && L_148_do_3B8<L_19_do_70 * L_201_do_1C98 + W_10_do )
           {
             Print("Slippage control active"); 
             W_2_bo = true ;
             L_148_do_3B8 = MarketInfo(L_330_st_2940,MODE_BID) - L_18_do_68 * L_201_do_1C98 ;
           }
           if ( L_84_in_220 >  0 && L_85_in_224 >= 0 && L_219_do_1CE8>L_148_do_3B8 + L_189_do_1918 + L_331_do_2950 && ( L_219_do_1CE8<W_10_do || !(L_81_bo_214) ) && L_219_do_1CE8<MarketInfo(L_330_st_2940,MODE_BID) - L_86_in_228 * L_201_do_1C98 - L_189_do_1918 - L_331_do_2950 && MarketInfo(L_330_st_2940,MODE_BID)<W_8_do - L_302_do_20A8 )
           {
             L_148_do_3B8 = L_219_do_1CE8 ;
             W_2_bo = true ;
           }
           if ( L_78_do_1F8>0.0 && L_30_in_B0 == 3 && MarketInfo(L_330_st_2940,MODE_BID)>L_78_do_1F8 * L_201_do_1C98 + W_10_do && L_79_do_200 * L_201_do_1C98 + W_10_do>W_7_do + L_331_do_2950 && MarketInfo(L_330_st_2940,MODE_BID)>L_79_do_200 * L_201_do_1C98 + W_10_do + L_189_do_1918 && MarketInfo(L_330_st_2940,MODE_BID)<W_8_do - L_302_do_20A8 && NormalizeDouble(L_79_do_200 * L_201_do_1C98 + W_10_do,L_147_in_3B0)>OrderStopLoss() )
           {
             L_148_do_3B8 = NormalizeDouble(L_79_do_200 * L_201_do_1C98 + W_10_do,L_147_in_3B0) ;
             L_202_in_1CA0 = OrderModify(W_9_do,W_10_do,L_148_do_3B8,W_8_do,0,0xFFFFFFFF) ;
             if ( L_202_in_1CA0 <= 0 )
             {
               Print("error when setting breakeven: \'" + ccbsw_19(GetLastError()) + "\' ..\'Exit_BE_start\' to close to \'Exit_BE_extra_pips\' ..trying again!"); 
             }
             W_2_bo = true ;
           }
           if ( L_78_do_1F8>0.0 && L_30_in_B0 == 2 && MarketInfo(L_330_st_2940,MODE_BID)>L_78_do_1F8 * L_201_do_1C98 + W_10_do && L_79_do_200 * L_201_do_1C98 + W_10_do>L_148_do_3B8 + L_331_do_2950 && MarketInfo(L_330_st_2940,MODE_BID)>L_79_do_200 * L_201_do_1C98 + W_10_do + L_189_do_1918 && MarketInfo(L_330_st_2940,MODE_BID)<W_8_do - L_302_do_20A8 )
           {
             L_148_do_3B8 = L_79_do_200 * L_201_do_1C98 + W_10_do ;
             W_2_bo = true ;
           }
           if ( !(W_2_bo) && ( L_92_in_264 == 1 || (L_92_in_264 == 2 && L_95_do_278 * L_201_do_1C98 + L_148_do_3B8<=L_96_do_280 * L_201_do_1C98 + (W_5_do + L_1_do_0)) ) )
           {
             L_233_in_1D28 ++;
             if ( MarketInfo(L_330_st_2940,MODE_BID)>L_95_do_278 * L_201_do_1C98 + L_148_do_3B8 + L_189_do_1918 && MarketInfo(L_330_st_2940,MODE_BID)<W_8_do - L_302_do_20A8 && ( L_93_do_268==0.0 || MarketInfo(L_330_st_2940,MODE_BID)>L_228_do_1D10 * L_201_do_1C98 + W_5_do ) && L_233_in_1D28 >= L_94_in_270 )
             {
               L_233_in_1D28 = 0 ;
               L_148_do_3B8 = L_95_do_278 * L_201_do_1C98 + L_148_do_3B8 ;
               W_2_bo = true ;
             }
           }
           if ( MarketInfo(L_330_st_2940,MODE_BID)<=L_148_do_3B8 )
           {
             RefreshRates(); 
             OrderClose(W_9_do,W_12_do,MarketInfo(L_330_st_2940,MODE_BID),L_1_do_0,0xFFFFFFFF); 
             return(true); 
           }
           if ( NormalizeDouble(W_4_do,L_147_in_3B0)!=NormalizeDouble(L_148_do_3B8,L_147_in_3B0) )
           {
             X_do_41 = NormalizeDouble(L_148_do_3B8,L_147_in_3B0);
             X_in_42 = W_9_do;
             for (X_in_43 = 0 ; X_in_43 < L_156_in_1548 ; X_in_43=X_in_43 + 1)
             {
               if ( L_153_do_400_si20si2[X_in_43][0]==X_in_42 )
               {
                 L_153_do_400_si20si2[X_in_43][1] = X_do_41;
                 break;
               }
             }
           }
         }
       }
     }
     if ( W_2_bo )
     {
       W_3_bo = true ;
     }
   }
   if ( W_2_bo )
   {
     W_3_bo = true ;
   }
 }
 return(W_3_bo); 
 }
//ccbsw_16 <<==--------   --------
 bool ccbsw_17()
 {
  bool      W_2_bo = false;
  bool      W_3_bo = false;
  double    W_4_do;
  double    W_5_do;
  int       W_6_in;
  double    W_7_do;
  double    W_8_do;
  double    W_9_do;
  double    W_10_do;
  string    W_11_st;
  double    W_12_do;
  datetime  W_13_da;
  int       W_14_in;
  int       W_15_in;
  string    W_16_st;
  double    W_17_do;
  double    W_18_do;
  bool      W_19_bo;
  bool      W_20_bo;
  double    W_21_do;
  bool      W_22_bo;
  double    W_23_do;
  double    W_24_do;
  double    W_25_do;
  double    W_26_do;
  int       W_27_in;
  double    W_28_do;
//----- -----
 int        X_in_1;
 int        X_in_2;
 int        X_in_3;
 double     X_do_4;
 double     X_do_5;
 int        X_in_6;
 int        X_in_7;
 int        X_in_8;
 int        X_in_9;
 int        X_in_10;
 string     X_st_11;
 double     X_do_12;
 int        X_in_13;
 int        X_in_14;
 double     X_do_15;
 int        X_in_16;
 int        X_in_17;
 int        X_in_18;
 int        X_in_19;
 int        X_in_20;
 string     X_st_21;
 int        X_in_22;
 double     X_do_23;
 double     X_do_24;
 int        X_in_25;
 double     X_do_26;
 bool       X_bo_27;
 int        X_in_28;
 int        X_in_29;
 double     X_do_30;
 int        X_in_31;
 int        X_in_32;
 int        X_in_33;
 double     X_do_34;
 double     X_do_35;
 int        X_in_36;
 double     X_do_37;
 bool       X_bo_38;
 int        X_in_39;
 int        X_in_40;
 double     X_do_41;
 int        X_in_42;
 int        X_in_43;

 W_4_do = 0.0 ;
 W_5_do = 0.0 ;
 for (W_6_in = 0 ; W_6_in < OrdersTotal() ; W_6_in ++)
 {
   if ( OrderSelect(W_6_in,0,0) == true )
   {
     W_2_bo = false ;
     W_7_do = NormalizeDouble(OrderStopLoss(),L_147_in_3B0) ;
     W_8_do = NormalizeDouble(OrderTakeProfit(),L_147_in_3B0) ;
     W_9_do = OrderTicket() ;
     W_10_do = NormalizeDouble(OrderOpenPrice(),L_147_in_3B0) ;
     W_11_st = OrderComment() ;
     W_12_do = OrderLots() ;
     W_13_da = OrderOpenTime() ;
     W_14_in = OrderType() ;
     W_15_in = OrderMagicNumber() ;
     W_16_st = OrderSymbol() ;
     if ( ( W_14_in == 5 || W_14_in == 3 ) && L_37_in_D4 == 2 && ( L_64_in_174 == 0 || (L_64_in_174 == 1 && W_16_st == L_330_st_2940) ) && ( W_15_in == L_65_in_178 || L_65_in_178 == 0 ) && ( W_11_st == L_66_st_180 || L_66_st_180 == "" ) )
     {
       if ( ( W_7_do==0.0 || W_7_do==0.0 ) )
       {
         W_7_do = NormalizeDouble(L_69_do_1A0 * L_201_do_1C98 + W_10_do,L_147_in_3B0) ;
         OrderModify(W_9_do,W_10_do,W_7_do,W_8_do,0,Green); 
       }
       if ( ( W_8_do==0.0 || W_8_do==0.0 ) )
       {
         W_8_do = NormalizeDouble(W_10_do - L_70_do_1A8 * L_201_do_1C98,L_147_in_3B0) ;
         OrderModify(W_9_do,W_10_do,W_7_do,W_8_do,0,Green); 
       }
     }
     if ( W_14_in == 1 && ( ( W_15_in == L_62_in_160 && L_37_in_D4 == 1 && W_16_st == L_330_st_2940 ) || (L_37_in_D4 == 2 && ( L_64_in_174 == 0 || (L_64_in_174 == 1 && W_16_st == L_330_st_2940) ) && ( W_15_in == L_65_in_178 || L_65_in_178 == 0 ) && (W_11_st == L_66_st_180 || L_66_st_180 == "")) ) )
     {
       if ( ( W_7_do==0.0 || W_7_do==0.0 ) )
       {
         W_7_do = NormalizeDouble(L_69_do_1A0 * L_201_do_1C98 + W_10_do,L_147_in_3B0) ;
         OrderModify(W_9_do,W_10_do,W_7_do,W_8_do,0,Green); 
       }
       if ( ( W_8_do==0.0 || W_8_do==0.0 ) )
       {
         W_8_do = NormalizeDouble(W_10_do - L_70_do_1A8 * L_201_do_1C98,L_147_in_3B0) ;
         OrderModify(W_9_do,W_10_do,W_7_do,W_8_do,0,Green); 
       }
       L_228_do_1D10 = L_93_do_268 ;
       if ( L_97_in_288 >  0 && TimeCurrent() >  W_13_da + L_97_in_288 * 60 )
       {
         L_228_do_1D10 = L_98_do_290 ;
       }
       X_in_1 = L_147_in_3B0;
       X_in_2 = W_9_do;
       for (X_in_3 = 0 ; X_in_3 < 100 ; X_in_3=X_in_3 + 1)
       {
         if ( !(L_155_do_F08_si100si2[X_in_3][0]==X_in_2) )   continue;
         X_do_4 = L_155_do_F08_si100si2[X_in_3][1];
         break;
         
       }
       X_do_4 = 0.0;
       W_17_do = NormalizeDouble(X_do_4,X_in_1) ;
       if ( W_17_do==0.0 )
       {
         X_do_5 = W_10_do;
         X_in_6 = W_9_do;
         for (X_in_7 = 0 ; X_in_7 < 100 ; X_in_7=X_in_7 + 1)
         {
           if ( !(L_155_do_F08_si100si2[X_in_7][0]==0.0) )   continue;
           L_155_do_F08_si100si2[X_in_7][0] = X_in_6;
           L_155_do_F08_si100si2[X_in_7][1] = X_do_5;
           break;
           
         }
         W_17_do = W_10_do ;
       }
       else
       {
         W_17_do = W_17_do - L_54_do_130 * L_201_do_1C98 ;
       }
       W_18_do = W_17_do - W_10_do ;
       W_19_bo = false ;
       if ( W_17_do>L_54_do_130 * L_201_do_1C98 && W_18_do>L_15_do_50 * L_201_do_1C98 )
       {
         W_19_bo = true ;
         if ( L_16_in_58 == 2 )
         {
           L_228_do_1D10 = -1000.0 ;
           Print("Slippage Mode 2 active"); 
         }
       }
       if ( L_20_bo_78 )
       {
         W_5_do = W_17_do ;
       }
       else
       {
         W_5_do = W_10_do ;
       }
       if ( W_7_do>NormalizeDouble((L_69_do_1A0 + L_31_do_B8) * L_201_do_1C98 + W_10_do + L_1_do_0,L_147_in_3B0) )
       {
         W_7_do = NormalizeDouble((L_69_do_1A0 + L_31_do_B8) * L_201_do_1C98 + W_10_do + L_1_do_0,L_147_in_3B0) ;
         OrderModify(W_9_do,W_10_do,W_7_do,W_8_do,0,0xFFFFFFFF); 
       }
       if ( MarketInfo(L_330_st_2940,MODE_ASK)>(L_69_do_1A0 + L_31_do_B8) * L_201_do_1C98 + W_10_do + L_1_do_0 )
       {
         RefreshRates(); 
         OrderClose(OrderTicket(),OrderLots(),MarketInfo(L_330_st_2940,MODE_ASK),L_1_do_0,Red); 
         return(true); 
       }
       W_20_bo = false ;
       if ( L_115_bo_2FC )
       {
         X_in_8 = W_9_do;
         X_in_9 = 0;
         for (X_in_10 = OrdersTotal() ; X_in_10 >= 0 ; X_in_10=X_in_10 - 1)
         {
           if ( OrderSelect(X_in_10,0,0) != true || OrderMagicNumber() != L_126_in_344 || OrderSymbol() != L_330_st_2940 )   continue;
           X_st_11 = OrderComment();
           if ( X_st_11 != IntegerToString(X_in_8,0,32) )   continue;
           X_in_9=X_in_9 + 1;
           
         }
         W_21_do = X_in_9 ;
         W_22_bo = false ;
         if ( !(L_152_bo_3C9) )
         {
           L_152_bo_3C9 = true ;
           L_150_in_3C4 = 1 ;
         }
         if ( W_21_do==0.0 )
         {
           L_150_in_3C4 = 1 ;
         }
         if ( MathFloor(W_21_do / 2.0)==W_21_do / 2.0 )
         {
           L_150_in_3C4 = 1 ;
         }
         else
         {
           L_150_in_3C4 = 0 ;
         }
         if ( L_152_bo_3C9 )
         {
           if ( W_21_do>0.0 )
           {
             X_do_12 = AccountEquity();
             if ( X_do_12>AccountBalance() + L_119_do_318 )
             {
               for (X_in_13 = OrdersTotal() ; X_in_13 >= 0 ; X_in_13=X_in_13 - 1)
               {
                 if ( OrderSelect(X_in_13,0,0) != true )   continue;
                 
                 if ( ( OrderMagicNumber() != L_62_in_160 && OrderMagicNumber() != L_126_in_344 && OrderMagicNumber() != L_125_in_340 ) )   continue;
                 
                 if ( OrderType() == 0 )
                 {
                   OrderClose(OrderTicket(),OrderLots(),MarketInfo(L_330_st_2940,MODE_BID),L_15_do_50,Red); 
                 }
                 if ( OrderType() != 1 )   continue;
                 OrderClose(OrderTicket(),OrderLots(),MarketInfo(L_330_st_2940,MODE_ASK),L_15_do_50,Red); 
                 
               }
             }
           }
           if ( W_21_do>0.0 )
           {
             X_in_14 = W_9_do;
             X_do_15 = 0.0;
             for (X_in_16 = OrdersTotal() ; X_in_16 >= 0 ; X_in_16=X_in_16 - 1)
             {
               if ( OrderSelect(X_in_16,0,0) != true )   continue;
               
               if ( OrderTicket() != X_in_14 )
               {
                 X_st_11 = OrderComment();
               if ( X_st_11 != IntegerToString(X_in_14,0,32) )   continue;
               }
               X_do_15 = X_do_15 + OrderProfit();
               
             }
             if ( X_do_15>L_119_do_318 )
             {
               Print("Closing zone"); 
               X_in_17 = W_9_do;
               for (X_in_18 = OrdersTotal() ; X_in_18 >= 0 ; X_in_18=X_in_18 - 1)
               {
                 if ( OrderSelect(X_in_18,0,0) != true )   continue;
                 
                 if ( OrderMagicNumber() == L_62_in_160 && OrderTicket() == X_in_17 )
                 {
                   OrderClose(OrderTicket(),OrderLots(),MarketInfo(L_330_st_2940,MODE_ASK),3,Red); 
                 }
                 if ( OrderMagicNumber() != L_126_in_344 )   continue;
                 X_st_11 = OrderComment();
                 if ( X_st_11 != IntegerToString(X_in_17,0,32) )   continue;
                 
                 if ( OrderType() == 0 )
                 {
                   OrderClose(OrderTicket(),OrderLots(),MarketInfo(L_330_st_2940,MODE_BID),L_15_do_50,Red); 
                 }
                 if ( OrderType() != 1 )   continue;
                 OrderClose(OrderTicket(),OrderLots(),MarketInfo(L_330_st_2940,MODE_ASK),L_15_do_50,Red); 
                 
               }
               L_152_bo_3C9 = false ;
               W_20_bo = true ;
             }
           }
           else
           {
             W_23_do = W_12_do * L_121_do_328 ;
             if ( L_120_in_320 == 2 )
             {
               W_23_do = (W_21_do + 1.0) * W_12_do + W_12_do ;
             }
             if ( L_120_in_320 == 3 )
             {
               W_23_do = W_12_do * (MathPow(L_121_do_328,W_21_do + 1.0)) ;
             }
             if ( L_150_in_3C4 == 0 )
             {
               W_24_do = W_17_do ;
               if ( MarketInfo(L_330_st_2940,MODE_BID)<W_17_do )
               {
                 if ( W_21_do>=L_122_in_330 )
                 {
                   for (X_in_19 = OrdersTotal() ; X_in_19 >= 0 ; X_in_19=X_in_19 - 1)
                   {
                     if ( OrderSelect(X_in_19,0,0) != true )   continue;
                     
                     if ( OrderMagicNumber() == L_62_in_160 && OrderTicket() == W_9_do )
                     {
                       OrderClose(OrderTicket(),OrderLots(),MarketInfo(L_330_st_2940,MODE_ASK),3,Red); 
                     }
                     if ( OrderMagicNumber() != L_126_in_344 )   continue;
                     X_st_11 = OrderComment();
                     if ( X_st_11 != IntegerToString(W_9_do,0,32) )   continue;
                     
                     if ( OrderType() == 0 )
                     {
                       OrderClose(OrderTicket(),OrderLots(),MarketInfo(L_330_st_2940,MODE_BID),L_15_do_50,Red); 
                     }
                     if ( OrderType() != 1 )   continue;
                     OrderClose(OrderTicket(),OrderLots(),MarketInfo(L_330_st_2940,MODE_ASK),L_15_do_50,Red); 
                     
                   }
                 }
                 else
                 {
                   OrderSend(L_330_st_2940,1,W_23_do,MarketInfo(L_330_st_2940,MODE_BID),L_15_do_50,0.0,0.0,IntegerToString(W_9_do,0,32),L_126_in_344,0,Green); 
                   L_150_in_3C4 = 1 ;
                   W_22_bo = true ;
                 }
               }
             }
             else
             {
               W_25_do = L_116_do_300 * L_201_do_1C98 + W_17_do - W_21_do * L_117_do_308 * L_201_do_1C98 ;
               if ( W_25_do<L_118_do_310 * L_201_do_1C98 + W_17_do )
               {
                 W_25_do = L_118_do_310 * L_201_do_1C98 + W_17_do ;
               }
               if ( MarketInfo(L_330_st_2940,MODE_ASK)>W_25_do )
               {
                 if ( W_21_do>=L_122_in_330 )
                 {
                   for (X_in_20 = OrdersTotal() ; X_in_20 >= 0 ; X_in_20=X_in_20 - 1)
                   {
                     if ( OrderSelect(X_in_20,0,0) != true )   continue;
                     
                     if ( OrderMagicNumber() == L_62_in_160 && OrderTicket() == W_9_do )
                     {
                       OrderClose(OrderTicket(),OrderLots(),MarketInfo(L_330_st_2940,MODE_ASK),3,Red); 
                     }
                     if ( OrderMagicNumber() != L_126_in_344 )   continue;
                     X_st_21 = OrderComment();
                     if ( X_st_21 != IntegerToString(W_9_do,0,32) )   continue;
                     
                     if ( OrderType() == 0 )
                     {
                       OrderClose(OrderTicket(),OrderLots(),MarketInfo(L_330_st_2940,MODE_BID),L_15_do_50,Red); 
                     }
                     if ( OrderType() != 1 )   continue;
                     OrderClose(OrderTicket(),OrderLots(),MarketInfo(L_330_st_2940,MODE_ASK),L_15_do_50,Red); 
                     
                   }
                 }
                 else
                 {
                   OrderSend(L_330_st_2940,0,W_23_do,MarketInfo(L_330_st_2940,MODE_ASK),L_15_do_50,0.0,0.0,IntegerToString(W_9_do,0,32),L_126_in_344,0,Green); 
                   L_150_in_3C4 = 0 ;
                   W_22_bo = true ;
                 }
               }
             }
           }
         }
         if ( ( W_21_do>0.0 || W_22_bo ) )
         {
           W_20_bo = true ;
         }
       }
       if ( !(W_20_bo) )
       {
         if ( ( L_30_in_B0 == 1 || (L_30_in_B0 != 2 && L_30_in_B0 != 3) ) )
         {
           X_in_22 = W_9_do;
           X_do_23 = L_69_do_1A0;
           X_do_24 = W_10_do;
           X_in_25 = 2;
           X_do_26 = 0.0;
           X_bo_27 = false;
           for (X_in_28 = 0 ; X_in_28 < L_156_in_1548 ; X_in_28=X_in_28 + 1)
           {
             if ( L_153_do_400_si20si2[X_in_28][0]==X_in_22 )
             {
               X_do_26 = L_153_do_400_si20si2[X_in_28][1];
               X_bo_27 = true;
               break;
             }
           }
           if ( !(X_bo_27) )
           {
             if ( X_in_25 == 1 )
             {
               X_do_26 = NormalizeDouble(X_do_24 - X_do_23 * L_201_do_1C98,L_147_in_3B0);
             }
             if ( X_in_25 == 2 )
             {
               X_do_26 = NormalizeDouble(X_do_23 * L_201_do_1C98 + X_do_24,L_147_in_3B0);
             }
             for (X_in_29 = 0 ; X_in_29 < L_156_in_1548 ; X_in_29=X_in_29 + 1)
             {
               if ( L_153_do_400_si20si2[X_in_29][0]==0.0 )
               {
                 L_153_do_400_si20si2[X_in_29][0] = X_in_22;
                 L_153_do_400_si20si2[X_in_29][1] = X_do_26;
                 break;
               }
             }
           }
           L_148_do_3B8 = X_do_26 ;
           W_4_do = L_148_do_3B8 ;
           if ( MarketInfo(L_330_st_2940,MODE_ASK)>W_4_do )
           {
             Print("Closing with virtual SL"); 
             RefreshRates(); 
             OrderClose(W_9_do,W_12_do,MarketInfo(L_330_st_2940,MODE_ASK),L_1_do_0,0xFFFFFFFF); 
             return(true); 
           }
           if ( L_89_do_248>0.0 && TimeCurrent() >= W_13_da + L_296_in_208C && MarketInfo(L_330_st_2940,MODE_ASK)<W_7_do - L_331_do_2950 - L_90_do_250 * L_201_do_1C98 && MarketInfo(L_330_st_2940,MODE_ASK)>W_8_do + L_302_do_20A8 && NormalizeDouble(MarketInfo(L_330_st_2940,MODE_ASK) + L_90_do_250 * L_201_do_1C98,L_147_in_3B0)<W_7_do )
           {
             W_7_do = NormalizeDouble(MarketInfo(L_330_st_2940,MODE_ASK) + L_90_do_250 * L_201_do_1C98,L_147_in_3B0) ;
             if ( W_7_do>MarketInfo(L_330_st_2940,MODE_ASK) + L_189_do_1918 )
             {
               L_202_in_1CA0 = OrderModify(W_9_do,W_10_do,W_7_do,W_8_do,0,0xFFFFFFFF) ;
               if ( L_202_in_1CA0 <= 0 )
               {
                 Print("TrailStop error: \'" + ccbsw_19(GetLastError()) + "\' when setting trailing Exit_TrailSL_after_X_Minutes_size loss.  Trying again!"); 
               }
               W_2_bo = true ;
             }
           }
           if ( L_72_do_1C0>0.0 && MarketInfo(L_330_st_2940,MODE_ASK)<W_7_do - L_331_do_2950 - (L_72_do_1C0 + L_75_do_1D8) * L_201_do_1C98 && MarketInfo(L_330_st_2940,MODE_ASK)<W_5_do - L_73_do_1C8 * L_201_do_1C98 && MarketInfo(L_330_st_2940,MODE_ASK)>W_8_do + L_302_do_20A8 && W_7_do>W_10_do - L_74_do_1D0 * L_201_do_1C98 && NormalizeDouble(L_72_do_1C0 * L_201_do_1C98 + MarketInfo(L_330_st_2940,MODE_ASK),L_147_in_3B0)<W_7_do )
           {
             W_7_do = NormalizeDouble(MarketInfo(L_330_st_2940,MODE_ASK) + L_72_do_1C0 * L_201_do_1C98,L_147_in_3B0) ;
             if ( W_7_do>MarketInfo(L_330_st_2940,MODE_ASK) + L_189_do_1918 )
             {
               L_202_in_1CA0 = OrderModify(W_9_do,W_10_do,W_7_do,W_8_do,0,0xFFFFFFFF) ;
               if ( L_202_in_1CA0 <= 0 )
               {
                 Print("TrailStop error: \'" + ccbsw_19(GetLastError()) + "\' when setting trailing Exit_stop loss.  Trying again!"); 
               }
               else
               {
                 W_26_do = NormalizeDouble(L_76_do_1E0 / 100.0 * L_192_do_195C_si99[L_321_in_2910],2) ;
                 if ( W_26_do<W_12_do && W_26_do>=MarketInfo(L_330_st_2940,MODE_LOTSTEP) )
                 {
                   OrderClose(W_9_do,W_26_do,MarketInfo(L_330_st_2940,MODE_ASK),L_15_do_50,Red); 
                   return(true); 
                 }
               }
               W_2_bo = true ;
             }
           }
           if ( W_19_bo && L_16_in_58 == 1 && L_18_do_68>0.0 && MarketInfo(L_330_st_2940,MODE_ASK)<W_7_do - L_331_do_2950 - L_18_do_68 * L_201_do_1C98 && MarketInfo(L_330_st_2940,MODE_ASK)<W_17_do - L_17_do_60 * L_201_do_1C98 && MarketInfo(L_330_st_2940,MODE_ASK)>W_8_do + L_302_do_20A8 && W_7_do>W_10_do - L_19_do_70 * L_201_do_1C98 && NormalizeDouble(MarketInfo(L_330_st_2940,MODE_ASK) + L_18_do_68 * L_201_do_1C98,L_147_in_3B0)<W_7_do )
           {
             W_7_do = NormalizeDouble(MarketInfo(L_330_st_2940,MODE_ASK) + L_18_do_68 * L_201_do_1C98,L_147_in_3B0) ;
             if ( W_7_do>MarketInfo(L_330_st_2940,MODE_ASK) + L_189_do_1918 )
             {
               L_202_in_1CA0 = OrderModify(W_9_do,W_10_do,W_7_do,W_8_do,0,0xFFFFFFFF) ;
               if ( L_202_in_1CA0 <= 0 )
               {
                 Print("TrailStop error: \'" + ccbsw_19(GetLastError()) + "\' when setting Slip TL.  Trying again!"); 
               }
               else
               {
                 Print("Slippage controle active"); 
               }
               W_2_bo = true ;
             }
           }
           if ( L_84_in_220 >  0 && L_85_in_224 >= 0 && L_218_do_1CE0<W_7_do - L_189_do_1918 - L_331_do_2950 && ( L_218_do_1CE0>W_10_do || !(L_81_bo_214) ) && L_218_do_1CE0>L_86_in_228 * L_201_do_1C98 + MarketInfo(L_330_st_2940,MODE_ASK) + L_189_do_1918 + L_331_do_2950 && MarketInfo(L_330_st_2940,MODE_ASK)>W_8_do + L_302_do_20A8 && NormalizeDouble(L_218_do_1CE0,L_147_in_3B0)<W_7_do )
           {
             W_7_do = NormalizeDouble(L_218_do_1CE0,L_147_in_3B0) ;
             if ( W_7_do>MarketInfo(L_330_st_2940,MODE_ASK) + L_189_do_1918 )
             {
               L_202_in_1CA0 = OrderModify(W_9_do,W_10_do,W_7_do,W_8_do,0,0xFFFFFFFF) ;
               if ( L_202_in_1CA0 <= 0 )
               {
                 Print("error: \'" + ccbsw_19(GetLastError()) + "\' when modifying stoploss"); 
               }
               W_2_bo = true ;
             }
           }
           if ( L_78_do_1F8>0.0 && MarketInfo(L_330_st_2940,MODE_ASK)<W_10_do - L_78_do_1F8 * L_201_do_1C98 && W_10_do - L_79_do_200 * L_201_do_1C98<W_7_do - L_331_do_2950 && MarketInfo(L_330_st_2940,MODE_ASK)<W_10_do - L_79_do_200 * L_201_do_1C98 - L_189_do_1918 && MarketInfo(L_330_st_2940,MODE_ASK)>W_8_do + L_302_do_20A8 && NormalizeDouble(W_10_do - L_79_do_200 * L_201_do_1C98,L_147_in_3B0)<W_7_do )
           {
             W_7_do = NormalizeDouble(W_10_do - L_79_do_200 * L_201_do_1C98,L_147_in_3B0) ;
             if ( W_7_do>MarketInfo(L_330_st_2940,MODE_ASK) + L_189_do_1918 )
             {
               L_202_in_1CA0 = OrderModify(W_9_do,W_10_do,W_7_do,W_8_do,0,0xFFFFFFFF) ;
               if ( L_202_in_1CA0 <= 0 )
               {
                 Print("error when setting breakeven: \'" + ccbsw_19(GetLastError()) + "\' ..\'Exit_BE_start\' to close to \'Exit_BE_extra_pips\' ..trying again!"); 
               }
               W_2_bo = true ;
             }
           }
           if ( !(W_2_bo) && ( L_92_in_264 == 1 || (L_92_in_264 == 2 && W_7_do - L_95_do_278 * L_201_do_1C98>=W_5_do - L_1_do_0 - L_96_do_280 * L_201_do_1C98) ) )
           {
             L_233_in_1D28 ++;
             if ( MarketInfo(L_330_st_2940,MODE_ASK)<W_7_do - L_95_do_278 * L_201_do_1C98 - L_189_do_1918 && MarketInfo(L_330_st_2940,MODE_ASK)>W_8_do + L_302_do_20A8 && ( L_93_do_268==0.0 || MarketInfo(L_330_st_2940,MODE_ASK)<W_5_do - L_228_do_1D10 * L_201_do_1C98 ) && L_233_in_1D28 >= L_94_in_270 && NormalizeDouble(W_7_do - L_95_do_278 * L_201_do_1C98,L_147_in_3B0)<W_7_do )
             {
               L_233_in_1D28 = 0 ;
               W_7_do = NormalizeDouble(W_7_do - L_95_do_278 * L_201_do_1C98,L_147_in_3B0) ;
               OrderModify(W_9_do,W_10_do,W_7_do,W_8_do,0,0xFFFFFFFF); 
               W_2_bo = true ;
             }
           }
           L_148_do_3B8 = W_7_do ;
           if ( MarketInfo(L_330_st_2940,MODE_ASK)>W_7_do )
           {
             Print("Closing with virtual SL"); 
             RefreshRates(); 
             OrderClose(W_9_do,W_12_do,MarketInfo(L_330_st_2940,MODE_ASK),L_1_do_0,0xFFFFFFFF); 
             return(true); 
           }
           if ( NormalizeDouble(W_4_do,L_147_in_3B0)!=NormalizeDouble(L_148_do_3B8,L_147_in_3B0) )
           {
             X_do_30 = NormalizeDouble(L_148_do_3B8,L_147_in_3B0);
             X_in_31 = W_9_do;
             for (X_in_32 = 0 ; X_in_32 < L_156_in_1548 ; X_in_32=X_in_32 + 1)
             {
               if ( L_153_do_400_si20si2[X_in_32][0]==X_in_31 )
               {
                 L_153_do_400_si20si2[X_in_32][1] = X_do_30;
                 break;
               }
             }
           }
           if ( W_2_bo && L_99_bo_298 )
           {
             return(true); 
           }
         }
         if ( ( L_30_in_B0 == 2 || L_30_in_B0 == 3 ) )
         {
           X_in_33 = W_9_do;
           X_do_34 = L_69_do_1A0;
           X_do_35 = W_10_do;
           X_in_36 = 2;
           X_do_37 = 0.0;
           X_bo_38 = false;
           for (X_in_39 = 0 ; X_in_39 < L_156_in_1548 ; X_in_39=X_in_39 + 1)
           {
             if ( L_153_do_400_si20si2[X_in_39][0]==X_in_33 )
             {
               X_do_37 = L_153_do_400_si20si2[X_in_39][1];
               X_bo_38 = true;
               break;
             }
           }
           if ( !(X_bo_38) )
           {
             if ( X_in_36 == 1 )
             {
               X_do_37 = NormalizeDouble(X_do_35 - X_do_34 * L_201_do_1C98,L_147_in_3B0);
             }
             if ( X_in_36 == 2 )
             {
               X_do_37 = NormalizeDouble(X_do_34 * L_201_do_1C98 + X_do_35,L_147_in_3B0);
             }
             for (X_in_40 = 0 ; X_in_40 < L_156_in_1548 ; X_in_40=X_in_40 + 1)
             {
               if ( L_153_do_400_si20si2[X_in_40][0]==0.0 )
               {
                 L_153_do_400_si20si2[X_in_40][0] = X_in_33;
                 L_153_do_400_si20si2[X_in_40][1] = X_do_37;
                 break;
               }
             }
           }
           L_148_do_3B8 = X_do_37 ;
           W_4_do = L_148_do_3B8 ;
           if ( MarketInfo(L_330_st_2940,MODE_ASK)>=W_4_do )
           {
             RefreshRates(); 
             OrderClose(W_9_do,W_12_do,MarketInfo(L_330_st_2940,MODE_ASK),L_1_do_0,0xFFFFFFFF); 
             return(true); 
           }
           W_27_in = TimeCurrent() - L_312_da_20F0 ;
           if ( W_27_in >= L_32_in_C0 )
           {
             if ( NormalizeDouble(L_148_do_3B8,L_147_in_3B0)<W_7_do - L_331_do_2950 )
             {
               OrderModify(W_9_do,W_10_do,NormalizeDouble(L_148_do_3B8,L_147_in_3B0),W_8_do,0,0xFFFFFFFF); 
             }
             L_312_da_20F0 = TimeCurrent() ;
           }
           if ( L_89_do_248>0.0 && TimeCurrent() >= W_13_da + L_296_in_208C && MarketInfo(L_330_st_2940,MODE_ASK)<L_148_do_3B8 - L_331_do_2950 - L_90_do_250 * L_201_do_1C98 && MarketInfo(L_330_st_2940,MODE_ASK)>W_8_do + L_302_do_20A8 )
           {
             L_148_do_3B8 = MarketInfo(L_330_st_2940,MODE_ASK) + L_90_do_250 * L_201_do_1C98 ;
             W_2_bo = true ;
           }
           if ( L_72_do_1C0>0.0 && MarketInfo(L_330_st_2940,MODE_ASK)<L_148_do_3B8 - L_331_do_2950 - (L_72_do_1C0 + L_75_do_1D8) * L_201_do_1C98 && MarketInfo(L_330_st_2940,MODE_ASK)<W_5_do - L_73_do_1C8 * L_201_do_1C98 && L_148_do_3B8>W_10_do - L_74_do_1D0 * L_201_do_1C98 )
           {
             L_148_do_3B8 = L_72_do_1C0 * L_201_do_1C98 + MarketInfo(L_330_st_2940,MODE_ASK) ;
             W_28_do = NormalizeDouble(L_76_do_1E0 / 100.0 * L_192_do_195C_si99[L_321_in_2910],2) ;
             if ( W_28_do<W_12_do && W_28_do>=MarketInfo(L_330_st_2940,MODE_LOTSTEP) )
             {
               OrderClose(W_9_do,W_28_do,MarketInfo(L_330_st_2940,MODE_BID),L_15_do_50,Red); 
               return(true); 
             }
             W_2_bo = true ;
           }
           if ( W_19_bo && L_16_in_58 == 1 && L_18_do_68>0.0 && MarketInfo(L_330_st_2940,MODE_ASK)<L_148_do_3B8 - L_331_do_2950 - L_18_do_68 * L_201_do_1C98 && MarketInfo(L_330_st_2940,MODE_ASK)<W_17_do - L_17_do_60 * L_201_do_1C98 && MarketInfo(L_330_st_2940,MODE_ASK)>W_8_do + L_302_do_20A8 && L_148_do_3B8>W_10_do - L_19_do_70 * L_201_do_1C98 )
           {
             Print("Slippage controle active"); 
             W_2_bo = true ;
             L_148_do_3B8 = MarketInfo(L_330_st_2940,MODE_ASK) + L_18_do_68 * L_201_do_1C98 ;
           }
           if ( L_84_in_220 >  0 && L_85_in_224 >= 0 && L_218_do_1CE0<L_148_do_3B8 - L_189_do_1918 - L_331_do_2950 && ( L_218_do_1CE0>W_10_do || !(L_81_bo_214) ) && L_218_do_1CE0>L_86_in_228 * L_201_do_1C98 + MarketInfo(L_330_st_2940,MODE_ASK) + L_189_do_1918 + L_331_do_2950 && MarketInfo(L_330_st_2940,MODE_ASK)>W_8_do + L_302_do_20A8 )
           {
             L_148_do_3B8 = L_218_do_1CE0 ;
             W_2_bo = true ;
           }
           if ( L_78_do_1F8>0.0 && L_30_in_B0 == 3 && MarketInfo(L_330_st_2940,MODE_ASK)<W_10_do - L_78_do_1F8 * L_201_do_1C98 && W_10_do - L_79_do_200 * L_201_do_1C98<W_7_do - L_331_do_2950 && MarketInfo(L_330_st_2940,MODE_ASK)<W_10_do - L_79_do_200 * L_201_do_1C98 - L_189_do_1918 && MarketInfo(L_330_st_2940,MODE_ASK)>W_8_do + L_302_do_20A8 && NormalizeDouble(W_10_do - L_79_do_200 * L_201_do_1C98,L_147_in_3B0)<L_148_do_3B8 )
           {
             L_148_do_3B8 = NormalizeDouble(W_10_do - L_79_do_200 * L_201_do_1C98,L_147_in_3B0) ;
             L_202_in_1CA0 = OrderModify(W_9_do,W_10_do,L_148_do_3B8,W_8_do,0,0xFFFFFFFF) ;
             if ( L_202_in_1CA0 <= 0 )
             {
               Print("error when setting breakeven: \'" + ccbsw_19(GetLastError()) + "\' ..\'Exit_BE_start\' to close to \'Exit_BE_extra_pips\' ..trying again!"); 
             }
             W_2_bo = true ;
           }
           if ( L_78_do_1F8>0.0 && L_30_in_B0 == 2 && MarketInfo(L_330_st_2940,MODE_ASK)<W_10_do - L_78_do_1F8 * L_201_do_1C98 && W_10_do - L_79_do_200 * L_201_do_1C98<L_148_do_3B8 - L_331_do_2950 && MarketInfo(L_330_st_2940,MODE_ASK)<W_10_do - L_79_do_200 * L_201_do_1C98 - L_189_do_1918 && MarketInfo(L_330_st_2940,MODE_ASK)>W_8_do + L_302_do_20A8 )
           {
             L_148_do_3B8 = W_10_do - L_79_do_200 * L_201_do_1C98 ;
             W_2_bo = true ;
           }
           if ( !(W_2_bo) && ( L_92_in_264 == 1 || (L_92_in_264 == 2 && L_148_do_3B8 - L_95_do_278 * L_201_do_1C98>=W_5_do - L_1_do_0 - L_96_do_280 * L_201_do_1C98) ) )
           {
             L_233_in_1D28 ++;
             if ( MarketInfo(L_330_st_2940,MODE_ASK)<L_148_do_3B8 - L_95_do_278 * L_201_do_1C98 - L_189_do_1918 && MarketInfo(L_330_st_2940,MODE_ASK)>W_8_do + L_302_do_20A8 && ( L_93_do_268==0.0 || MarketInfo(L_330_st_2940,MODE_ASK)<W_5_do - L_228_do_1D10 * L_201_do_1C98 ) && L_233_in_1D28 >= L_94_in_270 )
             {
               L_233_in_1D28 = 0 ;
               L_148_do_3B8 = L_148_do_3B8 - L_95_do_278 * L_201_do_1C98 ;
               W_2_bo = true ;
             }
           }
           if ( MarketInfo(L_330_st_2940,MODE_ASK)>=L_148_do_3B8 )
           {
             RefreshRates(); 
             OrderClose(W_9_do,W_12_do,MarketInfo(L_330_st_2940,MODE_ASK),L_1_do_0,0xFFFFFFFF); 
             return(true); 
           }
           if ( NormalizeDouble(W_4_do,L_147_in_3B0)!=NormalizeDouble(L_148_do_3B8,L_147_in_3B0) )
           {
             X_do_41 = NormalizeDouble(L_148_do_3B8,L_147_in_3B0);
             X_in_42 = W_9_do;
             for (X_in_43 = 0 ; X_in_43 < L_156_in_1548 ; X_in_43=X_in_43 + 1)
             {
               if ( L_153_do_400_si20si2[X_in_43][0]==X_in_42 )
               {
                 L_153_do_400_si20si2[X_in_43][1] = X_do_41;
                 break;
               }
             }
           }
         }
       }
     }
     if ( W_2_bo )
     {
       W_3_bo = true ;
     }
   }
   if ( W_2_bo )
   {
     W_3_bo = true ;
   }
 }
 return(W_3_bo); 
 }
//ccbsw_17 <<==--------   --------
 bool ccbsw_18()
 {
  bool      W_2_bo;
  datetime  W_3_da;
  int       W_4_in;
//----- -----
 bool       X_bo_1;
 bool       X_bo_2;
 bool       X_bo_3;
 bool       X_bo_4;
 bool       X_bo_5;
 bool       X_bo_6;

 if ( !(L_128_bo_354) )
 {
   return(true); 
 }
 W_2_bo = false ;
 W_3_da = 0 ;
 if ( L_129_in_358 == 2 )
 {
   W_3_da = TimeCurrent() ;
 }
 if ( L_129_in_358 == 0 )
 {
   TimeGMT(); 
 }
 if ( L_129_in_358 == 1 )
 {
   TimeLocal(); 
 }
 W_4_in = TimeHour(W_3_da) ;
 if ( TimeDayOfWeek(W_3_da) == 0 )
 {
   if ( L_131_in_360 <  L_132_in_364 && ( W_4_in < L_131_in_360 || W_4_in >= L_132_in_364 ) )
   {
     X_bo_1 = false;
   }
   else
   {
     if ( L_131_in_360 >  L_132_in_364 && W_4_in <  L_131_in_360 && W_4_in >= L_132_in_364 )
     {
       X_bo_1 = false;
     }
     else
     {
       if ( L_131_in_360 == L_132_in_364 )
       {
         X_bo_1 = false;
       }
       else
       {
         X_bo_1 = true;
       }
     }
   }
   if ( X_bo_1 )
   {
     W_2_bo = true ;
   }
 }
 if ( TimeDayOfWeek(W_3_da) == 1 )
 {
   if ( L_133_in_368 <  L_134_in_36C && ( W_4_in < L_133_in_368 || W_4_in >= L_134_in_36C ) )
   {
     X_bo_2 = false;
   }
   else
   {
     if ( L_133_in_368 >  L_134_in_36C && W_4_in <  L_133_in_368 && W_4_in >= L_134_in_36C )
     {
       X_bo_2 = false;
     }
     else
     {
       if ( L_133_in_368 == L_134_in_36C )
       {
         X_bo_2 = false;
       }
       else
       {
         X_bo_2 = true;
       }
     }
   }
   if ( X_bo_2 )
   {
     W_2_bo = true ;
   }
 }
 if ( TimeDayOfWeek(W_3_da) == 2 )
 {
   if ( L_135_in_370 <  L_136_in_374 && ( W_4_in < L_135_in_370 || W_4_in >= L_136_in_374 ) )
   {
     X_bo_3 = false;
   }
   else
   {
     if ( L_135_in_370 >  L_136_in_374 && W_4_in <  L_135_in_370 && W_4_in >= L_136_in_374 )
     {
       X_bo_3 = false;
     }
     else
     {
       if ( L_135_in_370 == L_136_in_374 )
       {
         X_bo_3 = false;
       }
       else
       {
         X_bo_3 = true;
       }
     }
   }
   if ( X_bo_3 )
   {
     W_2_bo = true ;
   }
 }
 if ( TimeDayOfWeek(W_3_da) == 3 )
 {
   if ( L_137_in_378 <  L_138_in_37C && ( W_4_in < L_137_in_378 || W_4_in >= L_138_in_37C ) )
   {
     X_bo_4 = false;
   }
   else
   {
     if ( L_137_in_378 >  L_138_in_37C && W_4_in <  L_137_in_378 && W_4_in >= L_138_in_37C )
     {
       X_bo_4 = false;
     }
     else
     {
       if ( L_137_in_378 == L_138_in_37C )
       {
         X_bo_4 = false;
       }
       else
       {
         X_bo_4 = true;
       }
     }
   }
   if ( X_bo_4 )
   {
     W_2_bo = true ;
   }
 }
 if ( TimeDayOfWeek(W_3_da) == 4 )
 {
   if ( L_139_in_380 <  L_140_in_384 && ( W_4_in < L_139_in_380 || W_4_in >= L_140_in_384 ) )
   {
     X_bo_5 = false;
   }
   else
   {
     if ( L_139_in_380 >  L_140_in_384 && W_4_in <  L_139_in_380 && W_4_in >= L_140_in_384 )
     {
       X_bo_5 = false;
     }
     else
     {
       if ( L_139_in_380 == L_140_in_384 )
       {
         X_bo_5 = false;
       }
       else
       {
         X_bo_5 = true;
       }
     }
   }
   if ( X_bo_5 )
   {
     W_2_bo = true ;
   }
 }
 if ( TimeDayOfWeek(W_3_da) == 5 )
 {
   if ( L_141_in_388 <  L_142_in_38C && ( W_4_in < L_141_in_388 || W_4_in >= L_142_in_38C ) )
   {
     X_bo_6 = false;
   }
   else
   {
     if ( L_141_in_388 >  L_142_in_38C && W_4_in <  L_141_in_388 && W_4_in >= L_142_in_38C )
     {
       X_bo_6 = false;
     }
     else
     {
       if ( L_141_in_388 == L_142_in_38C )
       {
         X_bo_6 = false;
       }
       else
       {
         X_bo_6 = true;
       }
     }
   }
   if ( X_bo_6 )
   {
     W_2_bo = true ;
   }
 }
 return(W_2_bo); 
 }
//ccbsw_18 <<==--------   --------
 string ccbsw_19( int S_0_in)
 {
  string    W_1_st;
//----- -----

 L_257_in_1DE8 ++;
 switch(S_0_in)
 {
   case 0 : case 1 :
   W_1_st = "no error" ;
     break;
   case 2 :
   W_1_st = "common error" ;
     break;
   case 3 :
   W_1_st = "invalid trade parameters" ;
     break;
   case 4 :
   W_1_st = "trade server is busy" ;
     break;
   case 5 :
   W_1_st = "old version of the client terminal" ;
     break;
   case 6 :
   W_1_st = "no connection with trade server" ;
     break;
   case 7 :
   W_1_st = "not enough rights" ;
     break;
   case 8 :
   W_1_st = "too frequent requests" ;
     break;
   case 9 :
   W_1_st = "malfunctional trade operation (never returned error)" ;
     break;
   case 64 :
   W_1_st = "account disabled" ;
     break;
   case 65 :
   W_1_st = "invalid account" ;
     break;
   case 128 :
   W_1_st = "trade timeout" ;
     break;
   case 129 :
   W_1_st = "invalid price" ;
     break;
   case 130 :
   W_1_st = "invalid stops" ;
     break;
   case 131 :
   W_1_st = "invalid trade volume" ;
     break;
   case 132 :
   W_1_st = "market is closed" ;
     break;
   case 133 :
   W_1_st = "trade is disabled" ;
     break;
   case 134 :
   W_1_st = "not enough money" ;
     break;
   case 135 :
   W_1_st = "price changed" ;
     break;
   case 136 :
   W_1_st = "off quotes" ;
     break;
   case 137 :
   W_1_st = "broker is busy (never returned error)" ;
     break;
   case 138 :
   W_1_st = "requote" ;
     break;
   case 139 :
   W_1_st = "order is locked" ;
     break;
   case 140 :
   W_1_st = "long positions only allowed" ;
     break;
   case 141 :
   W_1_st = "too many requests" ;
     break;
   case 145 :
   W_1_st = "modification denied because order too close to market" ;
     break;
   case 146 :
   W_1_st = "trade context is busy" ;
     break;
   case 147 :
   W_1_st = "expirations are denied by broker" ;
     break;
   case 148 :
   W_1_st = "amount of open and pending orders has reached the Exit_limit" ;
     break;
   case 149 :
   W_1_st = "hedging is prohibited" ;
     break;
   case 150 :
   W_1_st = "prohibited by FIFO rules" ;
     break;
   case 4000 :
   W_1_st = "no error (never generated code)" ;
     break;
   case 4001 :
   W_1_st = "wrong function pointer" ;
     break;
   case 4002 :
   W_1_st = "array index is out of range" ;
     break;
   case 4003 :
   W_1_st = "no memory for function call stack" ;
     break;
   case 4004 :
   W_1_st = "recursive stack overflow" ;
     break;
   case 4005 :
   W_1_st = "not enough stack for parameter" ;
     break;
   case 4006 :
   W_1_st = "no memory for parameter string" ;
     break;
   case 4007 :
   W_1_st = "no memory for temp string" ;
     break;
   case 4008 :
   W_1_st = "not initialized string" ;
     break;
   case 4009 :
   W_1_st = "not initialized string in array" ;
     break;
   case 4010 :
   W_1_st = "no memory for array\' string" ;
     break;
   case 4011 :
   W_1_st = "too long string" ;
     break;
   case 4012 :
   W_1_st = "remainder from zero divide" ;
     break;
   case 4013 :
   W_1_st = "zero divide" ;
     break;
   case 4014 :
   W_1_st = "unknown command" ;
     break;
   case 4015 :
   W_1_st = "wrong jump (never generated error)" ;
     break;
   case 4016 :
   W_1_st = "not initialized array" ;
     break;
   case 4017 :
   W_1_st = "dll calls are not allowed" ;
     break;
   case 4018 :
   W_1_st = "cannot load library" ;
     break;
   case 4019 :
   W_1_st = "cannot call function" ;
     break;
   case 4020 :
   W_1_st = "expert function calls are not allowed" ;
     break;
   case 4021 :
   W_1_st = "not enough memory for temp string returned from function" ;
     break;
   case 4022 :
   W_1_st = "system is busy (never generated error)" ;
     break;
   case 4050 :
   W_1_st = "invalid function parameters count" ;
     break;
   case 4051 :
   W_1_st = "invalid function parameter value" ;
     break;
   case 4052 :
   W_1_st = "string function internal error" ;
     break;
   case 4053 :
   W_1_st = "some array error" ;
     break;
   case 4054 :
   W_1_st = "incorrect series array using" ;
     break;
   case 4055 :
   W_1_st = "custom indicator error" ;
     break;
   case 4056 :
   W_1_st = "arrays are incompatible" ;
     break;
   case 4057 :
   W_1_st = "global variables processing error" ;
     break;
   case 4058 :
   W_1_st = "global variable not found" ;
     break;
   case 4059 :
   W_1_st = "function is not allowed in testing mode" ;
     break;
   case 4060 :
   W_1_st = "function is not confirmed" ;
     break;
   case 4061 :
   W_1_st = "send mail error" ;
     break;
   case 4062 :
   W_1_st = "string parameter expected" ;
     break;
   case 4063 :
   W_1_st = "integer parameter expected" ;
     break;
   case 4064 :
   W_1_st = "double parameter expected" ;
     break;
   case 4065 :
   W_1_st = "array as parameter expected" ;
     break;
   case 4066 :
   W_1_st = "requested history data in update state" ;
     break;
   case 4099 :
   W_1_st = "end of file" ;
     break;
   case 4100 :
   W_1_st = "some file error" ;
     break;
   case 4101 :
   W_1_st = "wrong file name" ;
     break;
   case 4102 :
   W_1_st = "too many opened files" ;
     break;
   case 4103 :
   W_1_st = "cannot open file" ;
     break;
   case 4104 :
   W_1_st = "incompatible access to a file" ;
     break;
   case 4105 :
   W_1_st = "no order selected" ;
     break;
   case 4106 :
   W_1_st = "unknown symbol" ;
     break;
   case 4107 :
   W_1_st = "invalid price parameter for trade function" ;
     break;
   case 4108 :
   W_1_st = "invalid ticket" ;
     break;
   case 4109 :
   W_1_st = "trade is not allowed in the expert properties" ;
     break;
   case 4110 :
   W_1_st = "longs are not allowed in the expert properties" ;
     break;
   case 4111 :
   W_1_st = "shorts are not allowed in the expert properties" ;
     break;
   case 4200 :
   W_1_st = "object is already exist" ;
     break;
   case 4201 :
   W_1_st = "unknown object property" ;
     break;
   case 4202 :
   W_1_st = "object is not exist" ;
     break;
   case 4203 :
   W_1_st = "unknown object type" ;
     break;
   case 4204 :
   W_1_st = "no object name" ;
     break;
   case 4205 :
   W_1_st = "object coordinates error" ;
     break;
   case 4206 :
   W_1_st = "no specified subwindow" ;
     break;
   default :
   W_1_st = "unknown error" ;
 }
 return(W_1_st);
 }
//ccbsw_19 <<==--------   --------
 void ccbsw_20( bool S_0_bo)
 {
  double    W_1_do;
  int       W_2_in;
  int       W_3_in;
  double    W_4_do;
  int       W_5_in;
  double    W_6_do;
  double    W_7_do;
  datetime  W_8_da;
  string    W_9_st;
  int       W_10_in;
  double    W_11_do;
  int       W_12_in;
  double    W_13_do;
  double    W_14_do;
  datetime  W_15_da;
  string    W_16_st;
  int       W_17_in;
//----- -----
 int        X_in_1;
 int        X_in_2;
 int        X_in_3;
 int        X_in_4;
 int        X_in_5;
 int        X_in_6;

 W_1_do = L_101_do_2A0 / 100.0 + 1.0 ;
 if ( ( !(AccountBalance()!=L_311_do_20E8) && !(S_0_bo) ) )   return;
 
 if ( ( !(AccountBalance()>L_311_do_20E8 * W_1_do) && !(AccountBalance()<L_311_do_20E8 / W_1_do) && !(S_0_bo) ) )   return;
 ccbsw_9(L_69_do_1A0,L_61_in_15C); 
 W_2_in = OrdersTotal() ;
 for (W_3_in = W_2_in ; W_3_in >= 0 ; W_3_in --)
 {
   if ( OrderSelect(W_3_in,0,0) != true || OrderMagicNumber() != L_62_in_160 || OrderSymbol() != L_330_st_2940 )   continue;
   
   if ( OrderType() == 4 && OrderLots()!=L_192_do_195C_si99[L_321_in_2910] )
   {
     W_4_do = OrderStopLoss() ;
     W_5_in = OrderTicket() ;
     W_6_do = OrderTakeProfit() ;
     W_7_do = OrderOpenPrice() ;
     W_8_da = OrderExpiration() ;
     W_9_st = OrderComment() ;
     OrderDelete(W_5_in,Red); 
     W_10_in = OrderSend(L_330_st_2940,4,L_192_do_195C_si99[L_321_in_2910],W_7_do,L_15_do_50,W_4_do,W_6_do,W_9_st,L_62_in_160,W_8_da,Green) ;
     X_in_1 = W_10_in;
     X_in_2 = W_5_in;
     for (X_in_3 = 0 ; X_in_3 < 100 ; X_in_3=X_in_3 + 1)
     {
       if ( !(L_155_do_F08_si100si2[X_in_3][0]==X_in_2) )   continue;
       L_155_do_F08_si100si2[X_in_3][0] = X_in_1;
       break;
       
     }
     Print("Lotsize changed more than " + string(L_101_do_2A0) + "%... adjusting lotsize of pending orders"); 
     Sleep(1000); 
   }
   if ( OrderType() != 5 || !(OrderLots()!=L_192_do_195C_si99[L_321_in_2910]) )   continue;
   W_11_do = OrderStopLoss() ;
   W_12_in = OrderTicket() ;
   W_13_do = OrderTakeProfit() ;
   W_14_do = OrderOpenPrice() ;
   W_15_da = OrderExpiration() ;
   W_16_st = OrderComment() ;
   OrderDelete(W_12_in,Red); 
   W_17_in = OrderSend(L_330_st_2940,5,L_192_do_195C_si99[L_321_in_2910],W_14_do,L_15_do_50,W_11_do,W_13_do,W_16_st,L_62_in_160,W_15_da,Green) ;
   X_in_4 = W_17_in;
   X_in_5 = W_12_in;
   for (X_in_6 = 0 ; X_in_6 < 100 ; X_in_6=X_in_6 + 1)
   {
     if ( !(L_155_do_F08_si100si2[X_in_6][0]==X_in_5) )   continue;
     L_155_do_F08_si100si2[X_in_6][0] = X_in_4;
     break;
     
   }
   Print("Lotsize changed more than " + string(L_101_do_2A0) + "%... adjusting lotsize of pending orders"); 
   Sleep(1000); 
   
 }
 }
//ccbsw_20 <<==--------   --------
 void ccbsw_21()
 {
  int       W_1_in = 0;
  int       W_2_in = 0;
  int       W_3_in;
  int       W_4_in;
  int       W_5_in;
  double    W_6_do;
  int       W_7_in;
  int       W_8_in;
  int       W_9_in;
  int       W_10_in;
  int       W_11_in;
  int       W_12_in;
  int       W_13_in;
  int       W_14_in;
  bool      W_15_bo;
  int       W_16_in;
  int       W_17_in;
  int       W_18_in;
  int       W_19_in;
  string    W_20_st;
  int       W_21_in;
  int       W_22_in;
  int       W_23_in;
//----- -----

 W_3_in = 20 ;
 W_4_in = 300 ;
 W_5_in = 7 ;
 W_6_do = InfoPanelSizeAdjust ;
 W_7_in = 6 ;
 W_8_in = 4 ;
 W_9_in = 350 ;
 W_10_in = 150 ;
 W_11_in = 0 ;
 W_12_in = 5 ;
 W_13_in = 20 ;
 W_14_in = 14599344 ;
 W_15_bo = false ;
 W_16_in = 0 ;
 if ( L_9_bo_2C )
 {
   W_16_in = (L_375_in_5590 + 3) * L_358_do_54D8 ;
 }
 ObjectCreate(0,"infopanel_rectangle",OBJ_RECTANGLE_LABEL,0,0,0.0); 
 ObjectSetInteger(0,"infopanel_rectangle",OBJPROP_XDISTANCE,W_12_in); 
 ObjectSetInteger(0,"infopanel_rectangle",OBJPROP_YDISTANCE,W_13_in); 
 ObjectSetInteger(0,"infopanel_rectangle",OBJPROP_XSIZE,long(W_9_in * InfoPanelSizeAdjust)); 
 ObjectSetInteger(0,"infopanel_rectangle",OBJPROP_YSIZE,double(W_10_in * InfoPanelSizeAdjust + W_16_in)); 
 ObjectSetInteger(0,"infopanel_rectangle",OBJPROP_CORNER,0); 
 ObjectSetInteger(0,"infopanel_rectangle",OBJPROP_COLOR,16711680); 
 ObjectSetInteger(0,"infopanel_rectangle",OBJPROP_BGCOLOR,W_14_in); 
 ObjectSetInteger(0,"infopanel_rectangle",OBJPROP_BACK,0); 
 ObjectSetInteger(0,"infopanel_rectangle",OBJPROP_BORDER_COLOR,16711680); 
 ObjectSetInteger(0,"infopanel_rectangle",OBJPROP_COLOR,16711680); 
 ObjectSetInteger(0,"infopanel_rectangle",OBJPROP_BORDER_TYPE,0); 
 ObjectSetInteger(0,"infopanel_rectangle",OBJPROP_STYLE,0); 
 ObjectSetInteger(0,"infopanel_rectangle",OBJPROP_WIDTH,2); 
 ObjectSetInteger(0,"infopanel_rectangle",OBJPROP_SELECTABLE,0); 
 ObjectCreate(0,"line1",OBJ_LABEL,0,0,0.0); 
 ObjectSetInteger(0,"line1",OBJPROP_CORNER,W_11_in); 
 ObjectSetInteger(0,"line1",OBJPROP_YDISTANCE,W_13_in + W_8_in); 
 ObjectSetInteger(0,"line1",OBJPROP_XDISTANCE,W_12_in + W_7_in); 
 if ( !(L_9_bo_2C) )
 {
   ObjectSetString(0,"line1",OBJPROP_TEXT,"Gold Trade Pro V1.31"); 
 }
 else
 {
   ObjectSetString(0,"line1",OBJPROP_TEXT,"Gold Trade Pro V1.31 - OneChartSetup"); 
 }
 ObjectSetInteger(0,"line1",OBJPROP_COLOR,L_322_in_2914); 
 ObjectCreate(0,"linec",OBJ_LABEL,0,0,0.0); 
 ObjectSetInteger(0,"linec",OBJPROP_CORNER,W_11_in); 
 ObjectSetInteger(0,"linec",OBJPROP_YDISTANCE,double(W_13_in + InfoPanelSizeAdjust * 20.0 + W_8_in)); 
 ObjectSetInteger(0,"linec",OBJPROP_XDISTANCE,W_12_in + W_7_in); 
 ObjectSetString(0,"linec",OBJPROP_TEXT,"EA Developed by Wim Schrynemakers - 2023"); 
 ObjectSetInteger(0,"linec",OBJPROP_COLOR,L_322_in_2914); 
 ObjectCreate(0,"line2",OBJ_LABEL,0,0,0.0); 
 ObjectSetInteger(0,"line2",OBJPROP_CORNER,W_11_in); 
 ObjectSetInteger(0,"line2",OBJPROP_YDISTANCE,double(W_13_in + InfoPanelSizeAdjust * 32.0 + W_8_in)); 
 ObjectSetInteger(0,"line2",OBJPROP_XDISTANCE,W_12_in + W_7_in); 
 ObjectSetString(0,"line2",OBJPROP_TEXT,"------------------------------------------------------"); 
 ObjectSetInteger(0,"line2",OBJPROP_COLOR,L_322_in_2914); 
 ObjectCreate(0,"lines",OBJ_LABEL,0,0,0.0); 
 ObjectSetInteger(0,"lines",OBJPROP_CORNER,W_11_in); 
 ObjectSetInteger(0,"lines",OBJPROP_YDISTANCE,double(W_13_in + InfoPanelSizeAdjust * 44.0 + W_8_in)); 
 ObjectSetInteger(0,"lines",OBJPROP_XDISTANCE,W_12_in + W_7_in); 
 if ( !(L_9_bo_2C) )
 {
   if ( Risk == 9999 )
   {
     ObjectSetString(0,"lines",OBJPROP_TEXT,"Current Lotsize: " + DoubleToString(NormalizeDouble(L_192_do_195C_si99[0],2),2) + " (using lotsizeStep=" + string(LotPerBalance_step) + ")"); 
   }
   else
   {
     if ( Risk == 999 )
     {
       ObjectSetString(0,"lines",OBJPROP_TEXT,"Current Lotsize: " + DoubleToString(NormalizeDouble(L_192_do_195C_si99[0],2),2) + " (Max_Risk/Trade=" + string(Manual_RiskPerTrade) + "%)"); 
     }
     else
     {
       if ( Risk == L_103_in_2B0 )
       {
         ObjectSetString(0,"lines",OBJPROP_TEXT,"Current Lotsize: " + DoubleToString(NormalizeDouble(L_192_do_195C_si99[0],2),2) + " (Max_Risk_DD_Based=" + string(L_104_do_2B8) + "%)"); 
       }
       else
       {
         ObjectSetString(0,"lines",OBJPROP_TEXT,"Current Lotsize: " + DoubleToString(NormalizeDouble(L_192_do_195C_si99[0],2),2) + " (using fixed lotsize)"); 
       }
     }
   }
 }
 else
 {
   if ( Risk == 9999 )
   {
     ObjectSetString(0,"lines",OBJPROP_TEXT,"Current Lotsize -> using lotsizeStep=" + string(LotPerBalance_step)); 
   }
   else
   {
     if ( Risk == 999 )
     {
       ObjectSetString(0,"lines",OBJPROP_TEXT,"Current Lotsize -> Max_Risk/Trade=" + string(Manual_RiskPerTrade) + "%"); 
     }
     else
     {
       if ( Risk == L_103_in_2B0 )
       {
         ObjectSetString(0,"lines",OBJPROP_TEXT,"Current Lotsize -> Max_Risk_DD_Based=" + string(L_104_do_2B8) + "%"); 
       }
       else
       {
         ObjectSetString(0,"lines",OBJPROP_TEXT,"Current Lotsize: " + DoubleToString(NormalizeDouble(L_192_do_195C_si99[0],2),2) + " (using fixed lotsize)"); 
       }
     }
   }
 }
 ObjectSetInteger(0,"lines",OBJPROP_COLOR,L_322_in_2914); 
 ObjectCreate(0,"lineopl" + IntegerToString(0,0,32),OBJ_LABEL,0,0,0.0); 
 ObjectSetInteger(0,"lineopl" + IntegerToString(0,0,32),OBJPROP_CORNER,W_11_in); 
 ObjectSetInteger(0,"lineopl" + IntegerToString(0,0,32),OBJPROP_YDISTANCE,W_13_in + InfoPanelSizeAdjust * 76.0 + W_8_in); 
 ObjectSetInteger(0,"lineopl" + IntegerToString(0,0,32),OBJPROP_XDISTANCE,W_12_in + W_7_in); 
 ObjectSetString(0,"lineopl" + IntegerToString(0,0,32),OBJPROP_TEXT,"Open P/L: -"); 
 ObjectSetInteger(0,"lineopl" + IntegerToString(0,0,32),OBJPROP_COLOR,L_322_in_2914); 
 ObjectCreate(0,"linea" + IntegerToString(0,0,32),OBJ_LABEL,0,0,0.0); 
 ObjectSetInteger(0,"linea" + IntegerToString(0,0,32),OBJPROP_CORNER,W_11_in); 
 ObjectSetInteger(0,"linea" + IntegerToString(0,0,32),OBJPROP_YDISTANCE,W_13_in + InfoPanelSizeAdjust * 92.0 + W_8_in); 
 ObjectSetInteger(0,"linea" + IntegerToString(0,0,32),OBJPROP_XDISTANCE,W_12_in + W_7_in); 
 ObjectSetString(0,"linea" + IntegerToString(0,0,32),OBJPROP_TEXT,"Account Balance: -"); 
 ObjectSetInteger(0,"linea" + IntegerToString(0,0,32),OBJPROP_COLOR,L_322_in_2914); 
 ObjectCreate(0,"linetp" + IntegerToString(0,0,32),OBJ_LABEL,0,0,0.0); 
 ObjectSetInteger(0,"linetp" + IntegerToString(0,0,32),OBJPROP_CORNER,W_11_in); 
 ObjectSetInteger(0,"linetp" + IntegerToString(0,0,32),OBJPROP_YDISTANCE,W_13_in + InfoPanelSizeAdjust * 108.0 + W_8_in); 
 ObjectSetInteger(0,"linetp" + IntegerToString(0,0,32),OBJPROP_XDISTANCE,W_12_in + W_7_in); 
 ObjectSetString(0,"linetp" + IntegerToString(0,0,32),OBJPROP_TEXT,"Total P/L so far: -"); 
 ObjectSetInteger(0,"linetp" + IntegerToString(0,0,32),OBJPROP_COLOR,L_322_in_2914); 
 if ( !(L_9_bo_2C) )   return;
 W_17_in = 0 ;
 W_18_in = 0 ;
 W_19_in = 0 ;
 W_21_in = W_12_in + W_7_in ;
 W_22_in = W_13_in + InfoPanelSizeAdjust * 160.0 + W_8_in ;
 W_20_st = "Pair" ;
 ccbsw_22(W_21_in,W_22_in,0,"Pair",0,0,1,0,1.0); 
 W_17_in = 1 ;
 W_18_in = 1 ;
 W_20_st = "Closed PL" ;
 if ( L_108_in_2D4 == 1 )
 {
   W_20_st = "Closed PL*" ;
 }
 ccbsw_22(W_21_in,W_22_in,W_17_in,W_20_st,W_19_in,W_18_in,1,0,1.0); 
 W_17_in ++;
 W_18_in ++;
 W_20_st = "PL per trade" ;
 if ( L_108_in_2D4 == 2 )
 {
   W_20_st = "PL per trade*" ;
 }
 ccbsw_22(W_21_in,W_22_in,W_17_in,W_20_st,W_19_in,W_18_in,1,0,1.0); 
 W_17_in ++;
 W_18_in ++;
 W_20_st = "Lotsize" ;
 ccbsw_22(W_21_in,W_22_in,W_17_in,"Lotsize",W_19_in,W_18_in,1,0,1.0); 
 W_17_in ++;
 W_18_in = 0 ;
 W_19_in ++;
 L_334_in_2B20 = W_17_in ;
 for (W_23_in = 0 ; W_23_in < L_375_in_5590 ; W_23_in ++)
 {
   W_20_st = L_372_st_554C_si4[W_23_in] ;
   ccbsw_22(W_21_in,W_22_in,W_17_in,W_20_st,W_19_in,W_18_in,1,0,1.0); 
   W_17_in ++;
   W_18_in ++;
   W_20_st = DoubleToString(NormalizeDouble(L_343_do_3EC4_si99[W_23_in],2),2) ;
   ccbsw_22(W_21_in,W_22_in,W_17_in,W_20_st,W_19_in,W_18_in,1,0,1.0); 
   W_17_in ++;
   W_18_in ++;
   W_20_st = DoubleToString(NormalizeDouble(L_339_do_32BC_si99[W_23_in],2),2) ;
   ccbsw_22(W_21_in,W_22_in,W_17_in,W_20_st,W_19_in,W_18_in,1,0,1.0); 
   W_17_in ++;
   W_18_in ++;
   W_20_st = DoubleToString(NormalizeDouble(L_192_do_195C_si99[W_23_in],2),2) ;
   ccbsw_22(W_21_in,W_22_in,W_17_in,W_20_st,W_19_in,W_18_in,1,0,1.0); 
   W_17_in ++;
   W_18_in = 0 ;
   W_19_in ++;
 }
 }
//ccbsw_21 <<==--------   --------
 void ccbsw_22( int S_0_in,int S_1_in,int S_2_in,string S_3_st,int S_4_in,int S_5_in,int S_6_in,int S_7_in,double S_8_do)
 {
 ObjectCreate(0,"info_ea" + IntegerToString(S_2_in,0,32),OBJ_EDIT,0,0,0.0); 
 ObjectSetInteger(0,"info_ea" + IntegerToString(S_2_in,0,32),OBJPROP_XDISTANCE,S_0_in + S_5_in * L_357_do_54D0); 
 ObjectSetInteger(0,"info_ea" + IntegerToString(S_2_in,0,32),OBJPROP_YDISTANCE,S_1_in + S_4_in * L_358_do_54D8); 
 ObjectSetString(0,"info_ea" + IntegerToString(S_2_in,0,32),OBJPROP_TEXT,S_3_st); 
 ObjectSetInteger(0,"info_ea" + IntegerToString(S_2_in,0,32),OBJPROP_BACK,0); 
 ObjectSetInteger(0,"info_ea" + IntegerToString(S_2_in,0,32),OBJPROP_COLOR,S_7_in); 
 ObjectSetInteger(0,"info_ea" + IntegerToString(S_2_in,0,32),OBJPROP_BGCOLOR,L_360_in_54E4); 
 ObjectSetInteger(0,"info_ea" + IntegerToString(S_2_in,0,32),OBJPROP_BORDER_COLOR,0); 
 ObjectSetInteger(0,"info_ea" + IntegerToString(S_2_in,0,32),OBJPROP_FONTSIZE,L_369_in_550C * S_8_do); 
 ObjectSetInteger(0,"info_ea" + IntegerToString(S_2_in,0,32),OBJPROP_READONLY,1); 
 ObjectSetInteger(0,"info_ea" + IntegerToString(S_2_in,0,32),OBJPROP_YSIZE,L_358_do_54D8); 
 ObjectSetInteger(0,"info_ea" + IntegerToString(S_2_in,0,32),OBJPROP_XSIZE,L_357_do_54D0); 
 ObjectSetInteger(0,"info_ea" + IntegerToString(S_2_in,0,32),OBJPROP_YSIZE,L_358_do_54D8); 
 if ( S_6_in == 0 )
 {
   ObjectSetInteger(0,"info_ea" + IntegerToString(S_2_in,0,32),OBJPROP_ALIGN,1); 
 }
 if ( S_6_in == 1 )
 {
   ObjectSetInteger(0,"info_ea" + IntegerToString(S_2_in,0,32),OBJPROP_ALIGN,2); 
 }
 if ( S_6_in != 2 )   return;
 ObjectSetInteger(0,"info_ea" + IntegerToString(S_2_in,0,32),OBJPROP_ALIGN,0); 
 }
//ccbsw_22 <<==--------   --------
 void ccbsw_23()
 {
  int       W_1_in;
  int       W_2_in;
  int       W_3_in;
  int       W_4_in;
//----- -----

 ObjectDelete(0,"line1"); 
 ObjectDelete(0,"linec"); 
 ObjectDelete(0,"line2"); 
 ObjectDelete(0,"lines"); 
 ObjectDelete(0,"lineTradeStart"); 
 for (W_1_in = 0 ; W_1_in <= 99 ; W_1_in ++)
 {
   ObjectDelete(0,"lineopl" + IntegerToString(W_1_in,0,32)); 
   ObjectDelete(0,"linea" + IntegerToString(W_1_in,0,32)); 
   ObjectDelete(0,"lineto" + IntegerToString(W_1_in,0,32)); 
   ObjectDelete(0,"linetp" + IntegerToString(W_1_in,0,32)); 
   ObjectDelete(0,"linetq" + IntegerToString(W_1_in,0,32)); 
   for (W_2_in = 0 ; W_2_in < 10 ; W_2_in ++)
   {
     ObjectDelete(0,"tabel_info" + IntegerToString(W_1_in * 100 + W_2_in,0,32)); 
   }
 }
 ObjectDelete(0,"infopanel_rectangle"); 
 for (W_3_in = 0 ; W_3_in < 10 ; W_3_in ++)
 {
   ObjectDelete(0,"tabel_heading" + IntegerToString(W_3_in,0,32)); 
   ObjectDelete(0,"tabel_totals" + IntegerToString(W_3_in,0,32)); 
 }
 for (W_4_in = 0 ; W_4_in < L_356_in_54C8 ; W_4_in ++)
 {
   ObjectDelete(0,"horizontalrect" + IntegerToString(W_4_in,0,32)); 
   ObjectDelete(0,"info_ea" + IntegerToString(W_4_in,0,32)); 
 }
 }
//ccbsw_23 <<==--------   --------
 void ccbsw_24()
 {
 double     X_do_1;
 int        X_in_2;
 int        X_in_3;
 int        X_in_4;
 int        X_in_5;
 int        X_in_6;
 int        X_in_7;
 int        X_in_8;
 int        X_in_9;
 int        X_in_10;
 int        X_in_11;

 if ( !(ShowInfoPanel) )   return;
 
 if ( ( MQLInfoInteger(MQL_TESTER) == 1 && !(UpdateInfoTesting) ) )   return;
 X_do_1 = 0.0;
 for (X_in_2 = OrdersTotal() ; X_in_2 >= 0 ; X_in_2=X_in_2 - 1)
 {
   if ( OrderSelect(X_in_2,0,0) != true )   continue;
   
   if ( ( OrderSymbol() != L_330_st_2940 && !(L_9_bo_2C) ) )   continue;
   X_in_3 = OrderMagicNumber();
   X_in_4=ST1_MagicNumber + 1;
   if ( X_in_3 != X_in_4 )
   {
     X_in_4 = OrderMagicNumber();
     X_in_5=ST1_MagicNumber + 2;
     if ( X_in_4 != X_in_5 )
     {
       X_in_5 = OrderMagicNumber();
       X_in_6=ST1_MagicNumber + 3;
       if ( X_in_5 != X_in_6 )
       {
         X_in_6 = OrderMagicNumber();
         X_in_7=ST1_MagicNumber + 4;
         if ( X_in_6 != X_in_7 )
         {
           X_in_7 = OrderMagicNumber();
           X_in_8=ST1_MagicNumber + 5;
           if ( X_in_7 != X_in_8 )
           {
             X_in_8 = OrderMagicNumber();
             X_in_9=ST1_MagicNumber + 6;
             if ( X_in_8 != X_in_9 )
             {
               X_in_9 = OrderMagicNumber();
               X_in_10=ST1_MagicNumber + 7;
               if ( X_in_9 != X_in_10 )
               {
                 X_in_10 = OrderMagicNumber();
                 X_in_11=ST1_MagicNumber + 8;
               if ( X_in_10 != X_in_11 )   continue;
               }
             }
           }
         }
       }
     }
   }
   if ( ( OrderType() != 0 && OrderType() != 1 ) )   continue;
   X_do_1 = OrderProfit() + OrderSwap() + OrderCommission() + X_do_1;
   
 }
 L_316_do_24B0_si30[L_321_in_2910] = X_do_1;
 ObjectSetString(0,"lineopl" + IntegerToString(0,0,32),OBJPROP_TEXT,"Open P/L: " + DoubleToString(X_do_1,2)); 
 ObjectSetString(0,"linea" + IntegerToString(0,0,32),OBJPROP_TEXT,"Account Balance: " + DoubleToString(AccountBalance(),2)); 
 if ( !(L_9_bo_2C) )
 {
   if ( Risk == 9999 )
   {
     ObjectSetString(0,"lines",OBJPROP_TEXT,"Current Lotsize: " + DoubleToString(NormalizeDouble(L_192_do_195C_si99[0],2),2) + " (using lotsizeStep=" + string(LotPerBalance_step) + ")"); 
     return;
   }
   if ( Risk == 999 )
   {
     ObjectSetString(0,"lines",OBJPROP_TEXT,"Current Lotsize: " + DoubleToString(NormalizeDouble(L_192_do_195C_si99[0],2),2) + " (Max_Risk/Trade=" + string(Manual_RiskPerTrade) + "%)"); 
     return;
   }
   if ( Risk == L_103_in_2B0 )
   {
     ObjectSetString(0,"lines",OBJPROP_TEXT,"Current Lotsize: " + DoubleToString(NormalizeDouble(L_192_do_195C_si99[0],2),2) + " (Max_Risk_DD_Based=" + string(L_104_do_2B8) + "%)"); 
     return;
   }
   ObjectSetString(0,"lines",OBJPROP_TEXT,"Current Lotsize: " + DoubleToString(NormalizeDouble(L_192_do_195C_si99[0],2),2) + " (using fixed lotsize)"); 
   return;
 }
 if ( Risk == 9999 )
 {
   ObjectSetString(0,"lines",OBJPROP_TEXT,"Current Lotsize -> using lotsizeStep=" + string(LotPerBalance_step)); 
   return;
 }
 if ( Risk == 999 )
 {
   ObjectSetString(0,"lines",OBJPROP_TEXT,"Current Lotsize -> Max_Risk/Trade=" + string(Manual_RiskPerTrade) + "%"); 
   return;
 }
 if ( Risk == L_103_in_2B0 )
 {
   ObjectSetString(0,"lines",OBJPROP_TEXT,"Current Lotsize -> Max_Risk_DD_Based=" + string(L_104_do_2B8) + "%"); 
   return;
 }
 ObjectSetString(0,"lines",OBJPROP_TEXT,"Current Lotsize: " + DoubleToString(NormalizeDouble(L_192_do_195C_si99[L_333_in_2994_si99[0]],2),2) + " (using fixed lotsize)"); 
 }
//ccbsw_24 <<==--------   --------
 void ccbsw_25()
 {
  int       W_1_in;
  string    W_2_st;
  int       W_3_in;
//----- -----

 if ( !(ShowInfoPanel) )   return;
 
 if ( ( MQLInfoInteger(MQL_TESTER) == 1 && !(UpdateInfoTesting) ) || !(L_9_bo_2C) )   return;
 W_1_in = L_334_in_2B20 ;
 for (W_3_in = 0 ; W_3_in < L_375_in_5590 ; W_3_in ++)
 {
   W_2_st = L_372_st_554C_si4[W_3_in] ;
   if ( L_342_bo_3E2C_si99[L_333_in_2994_si99[W_3_in]] != 0x0 )
   {
     ObjectSetInteger(0,"info_ea" + IntegerToString(W_1_in,0,32),OBJPROP_BGCOLOR,255); 
   }
   else
   {
     ObjectSetInteger(0,"info_ea" + IntegerToString(W_1_in,0,32),OBJPROP_BGCOLOR,L_360_in_54E4); 
   }
   ObjectSetString(0,"info_ea" + IntegerToString(W_1_in,0,32),OBJPROP_TEXT,W_2_st); 
   W_1_in ++;
   W_2_st = DoubleToString(NormalizeDouble(L_343_do_3EC4_si99[W_3_in],2),2) ;
   ObjectSetString(0,"info_ea" + IntegerToString(W_1_in,0,32),OBJPROP_TEXT,W_2_st); 
   W_1_in ++;
   W_2_st = DoubleToString(NormalizeDouble(L_339_do_32BC_si99[W_3_in],2),2) ;
   ObjectSetString(0,"info_ea" + IntegerToString(W_1_in,0,32),OBJPROP_TEXT,W_2_st); 
   W_1_in ++;
   W_2_st = DoubleToString(NormalizeDouble(L_192_do_195C_si99[W_3_in],2),2) ;
   ObjectSetString(0,"info_ea" + IntegerToString(W_1_in,0,32),OBJPROP_TEXT,W_2_st); 
   W_1_in ++;
 }
 }
//ccbsw_25 <<==--------   --------
 void ccbsw_26()
 {
 int        X_in_1;
 double     X_do_2;
 int        X_in_3;
 int        X_in_4;
 int        X_in_5;
 int        X_in_6;
 int        X_in_7;
 int        X_in_8;
 int        X_in_9;
 int        X_in_10;
 int        X_in_11;
 int        X_in_12;
 int        X_in_13;
 int        X_in_14;
 string     X_st_15;
 int        X_in_16;
 double     X_do_17;
 int        X_in_18;
 int        X_in_19;
 int        X_in_20;
 int        X_in_21;
 int        X_in_22;
 int        X_in_23;
 int        X_in_24;
 int        X_in_25;
 int        X_in_26;
 int        X_in_27;
 int        X_in_28;
 int        X_in_29;
 int        X_in_30;
 double     X_do_31;
 int        X_in_32;
 int        X_in_33;
 int        X_in_34;
 int        X_in_35;
 int        X_in_36;
 int        X_in_37;
 int        X_in_38;
 int        X_in_39;
 int        X_in_40;
 int        X_in_41;
 int        X_in_42;

 if ( !(ShowInfoPanel) )   return;
 
 if ( ( MQLInfoInteger(MQL_TESTER) == 1 && !(UpdateInfoTesting) ) )   return;
 X_in_1 = 9999999;
 X_do_2 = 0.0;
 X_in_3 = 0;
 X_in_4 = 0;
 for (X_in_5 = HistoryTotal() ; X_in_5 >= 0 ; X_in_5=X_in_5 - 1)
 {
   if ( OrderSelect(X_in_5,0,1) != true )   continue;
   
   if ( ( OrderSymbol() != L_330_st_2940 && !(L_9_bo_2C) ) )   continue;
   X_in_6 = OrderMagicNumber();
   X_in_7=ST1_MagicNumber + 1;
   if ( X_in_6 != X_in_7 )
   {
     X_in_7 = OrderMagicNumber();
     X_in_8=ST1_MagicNumber + 2;
     if ( X_in_7 != X_in_8 )
     {
       X_in_8 = OrderMagicNumber();
       X_in_9=ST1_MagicNumber + 3;
       if ( X_in_8 != X_in_9 )
       {
         X_in_9 = OrderMagicNumber();
         X_in_10=ST1_MagicNumber + 4;
         if ( X_in_9 != X_in_10 )
         {
           X_in_10 = OrderMagicNumber();
           X_in_11=ST1_MagicNumber + 5;
           if ( X_in_10 != X_in_11 )
           {
             X_in_11 = OrderMagicNumber();
             X_in_12=ST1_MagicNumber + 6;
             if ( X_in_11 != X_in_12 )
             {
               X_in_12 = OrderMagicNumber();
               X_in_13=ST1_MagicNumber + 7;
               if ( X_in_12 != X_in_13 )
               {
                 X_in_13 = OrderMagicNumber();
                 X_in_14=ST1_MagicNumber + 8;
               if ( X_in_13 != X_in_14 )   continue;
               }
             }
           }
         }
       }
     }
   }
   X_in_3=X_in_3 + 1;
   if ( ( OrderType() == 0 || OrderType() == 1 ) )
   {
     if ( OrderType() == 0 )
     {
       X_do_2 = OrderClosePrice() - OrderOpenPrice();
     }
     else
     {
       if ( OrderType() == 1 )
       {
         X_do_2 = OrderOpenPrice() - OrderClosePrice();
       }
     }
     if ( X_do_2>0.0 )
     {
       X_in_4=X_in_4 + 1;
     }
   }
   if ( X_in_3 >= X_in_1 )   break;
   
 }
 L_317_do_25D4_si30[L_321_in_2910] = X_in_4;
 X_st_15="Total profits/losses so far: " + IntegerToString(X_in_4,0,32) + "/";
 X_in_16 = 9999999;
 X_do_17 = 0.0;
 X_in_18 = 0;
 X_in_19 = 0;
 for (X_in_20 = HistoryTotal() ; X_in_20 >= 0 ; X_in_20=X_in_20 - 1)
 {
   if ( OrderSelect(X_in_20,0,1) != true )   continue;
   
   if ( ( OrderSymbol() != L_330_st_2940 && !(L_9_bo_2C) ) )   continue;
   X_in_21 = OrderMagicNumber();
   X_in_22=ST1_MagicNumber + 1;
   if ( X_in_21 != X_in_22 )
   {
     X_in_22 = OrderMagicNumber();
     X_in_23=ST1_MagicNumber + 2;
     if ( X_in_22 != X_in_23 )
     {
       X_in_23 = OrderMagicNumber();
       X_in_24=ST1_MagicNumber + 3;
       if ( X_in_23 != X_in_24 )
       {
         X_in_24 = OrderMagicNumber();
         X_in_25=ST1_MagicNumber + 4;
         if ( X_in_24 != X_in_25 )
         {
           X_in_25 = OrderMagicNumber();
           X_in_26=ST1_MagicNumber + 5;
           if ( X_in_25 != X_in_26 )
           {
             X_in_26 = OrderMagicNumber();
             X_in_27=ST1_MagicNumber + 6;
             if ( X_in_26 != X_in_27 )
             {
               X_in_27 = OrderMagicNumber();
               X_in_28=ST1_MagicNumber + 7;
               if ( X_in_27 != X_in_28 )
               {
                 X_in_28 = OrderMagicNumber();
                 X_in_29=ST1_MagicNumber + 8;
               if ( X_in_28 != X_in_29 )   continue;
               }
             }
           }
         }
       }
     }
   }
   X_in_18=X_in_18 + 1;
   if ( OrderType() == 0 )
   {
     X_do_17 = OrderClosePrice() - OrderOpenPrice();
   }
   else
   {
     if ( OrderType() == 1 )
     {
       X_do_17 = OrderOpenPrice() - OrderClosePrice();
     }
   }
   if ( X_do_17<0.0 )
   {
     X_in_19=X_in_19 + 1;
   }
   if ( X_in_18 >= X_in_16 )   break;
   
 }
 L_318_do_26F8_si30[L_321_in_2910] = X_in_19;
 X_st_15=X_st_15 + IntegerToString(X_in_19,0,32);
 ObjectSetString(0,"lineto" + IntegerToString(0,0,32),OBJPROP_TEXT,X_st_15); 
 X_in_30 = 1000;
 X_do_31 = 0.0;
 X_in_32 = 0;
 for (X_in_33 = HistoryTotal() ; X_in_33 >= 0 ; X_in_33=X_in_33 - 1)
 {
   if ( OrderSelect(X_in_33,0,1) != true )   continue;
   
   if ( ( OrderSymbol() != L_330_st_2940 && !(L_9_bo_2C) ) )   continue;
   X_in_34 = OrderMagicNumber();
   X_in_35=ST1_MagicNumber + 1;
   if ( X_in_34 != X_in_35 )
   {
     X_in_35 = OrderMagicNumber();
     X_in_36=ST1_MagicNumber + 2;
     if ( X_in_35 != X_in_36 )
     {
       X_in_36 = OrderMagicNumber();
       X_in_37=ST1_MagicNumber + 3;
       if ( X_in_36 != X_in_37 )
       {
         X_in_37 = OrderMagicNumber();
         X_in_38=ST1_MagicNumber + 4;
         if ( X_in_37 != X_in_38 )
         {
           X_in_38 = OrderMagicNumber();
           X_in_39=ST1_MagicNumber + 5;
           if ( X_in_38 != X_in_39 )
           {
             X_in_39 = OrderMagicNumber();
             X_in_40=ST1_MagicNumber + 6;
             if ( X_in_39 != X_in_40 )
             {
               X_in_40 = OrderMagicNumber();
               X_in_41=ST1_MagicNumber + 7;
               if ( X_in_40 != X_in_41 )
               {
                 X_in_41 = OrderMagicNumber();
                 X_in_42=ST1_MagicNumber + 8;
               if ( X_in_41 != X_in_42 )   continue;
               }
             }
           }
         }
       }
     }
   }
   X_in_32=X_in_32 + 1;
   X_do_31 = X_do_31 + OrderProfit() + OrderSwap() + OrderCommission();
   if ( X_in_32 >= X_in_30 )   break;
   
 }
 L_319_do_281C_si30[L_321_in_2910] = X_do_31;
 ObjectSetString(0,"linetp" + IntegerToString(0,0,32),OBJPROP_TEXT,"Total P/L so far: " + DoubleToString(NormalizeDouble(X_do_31,2),2)); 
 }
//ccbsw_26 <<==--------   --------
 void ccbsw_27()
 {
  int       W_1_in = 0;
  double    W_2_do_si99[99];
  double    W_3_do_si99[99];
  int       W_4_in;
  int       W_5_in;
  bool      W_6_bo;
  int       W_7_in;
  double    W_8_do;
  int       W_9_in;
  int       W_10_in;
//----- -----
 long       X_lo_1;
 long       X_lo_2;
 long       X_lo_3;
 long       X_lo_4;
 long       X_lo_5;

 for (W_4_in = 0 ; W_4_in < L_375_in_5590 ; W_4_in ++)
 {
   W_2_do_si99[W_4_in] = 0.0;
   W_3_do_si99[W_4_in] = 0.0;
   L_336_bo_2EA4_si99[W_4_in] = false;
   L_337_in_2F3C_si99[W_4_in] = 0;
   L_338_in_30FC_si99[W_4_in] = 0;
 }
 for (W_5_in = HistoryTotal() ; W_5_in >= 0 ; W_5_in --)
 {
   if ( OrderSelect(W_5_in,0,1) != true || OrderMagicNumber() != L_62_in_160 )   continue;
   W_6_bo = true ;
   for (W_7_in = 0 ; W_7_in < L_375_in_5590 ; W_7_in ++)
   {
     if ( L_336_bo_2EA4_si99[W_7_in] == 0x0 )
     {
       W_6_bo = false ;
     }
   }
   if ( ( OrderCloseTime() <  TimeCurrent() - L_109_in_2D8 * 24 * 60 * 60 && W_6_bo ) )   break;
   W_8_do = OrderLots() * 100.0 ;
   if ( L_107_in_2D0 == 1 )
   {
     W_8_do = 1.0 ;
   }
   W_9_in = 0 ;
   if ( L_375_in_5590 <= 0 )   continue;
   
   for ( ; W_9_in < L_375_in_5590 ; W_9_in ++)
   {
     if ( L_341_st_3954_si99[W_9_in] != OrderSymbol() )   continue;
     
     if ( ( OrderType() != 0 && OrderType() != 1 ) )   continue;
     X_lo_1 = OrderCloseTime();
     X_lo_2=TimeCurrent() - L_109_in_2D8 * 24 * 60 * 60;
     if ( X_lo_1 <  X_lo_2 )
     {
       X_lo_2 = OrderCloseTime();
       X_lo_3=TimeCurrent() - L_109_in_2D8 * 24 * 60 * 60;
     if ( (X_lo_2 >= X_lo_3 || L_336_bo_2EA4_si99[W_9_in] != 0x0) )   continue;
     }
     L_337_in_2F3C_si99[W_9_in] ++;
     if ( L_337_in_2F3C_si99[W_9_in] >= L_111_in_2E0 )
     {
       L_336_bo_2EA4_si99[W_9_in] = true;
     }
     W_2_do_si99[W_9_in] +=OrderProfit() / W_8_do;
     W_2_do_si99[W_9_in] +=OrderSwap() / W_8_do;
     W_2_do_si99[W_9_in] +=OrderCommission() / W_8_do;
     X_lo_4 = OrderCloseTime();
     X_lo_5=TimeCurrent() - L_110_in_2DC * 24 * 60 * 60;
     if ( X_lo_4 < X_lo_5 )   continue;
     W_3_do_si99[W_9_in] +=OrderProfit() / W_8_do;
     W_3_do_si99[W_9_in] +=OrderSwap() / W_8_do;
     W_3_do_si99[W_9_in] +=OrderCommission() / W_8_do;
     L_338_in_30FC_si99[W_9_in] ++;
     
   }
   
 }
 for (W_10_in = 0 ; W_10_in < L_375_in_5590 ; W_10_in ++)
 {
   L_343_do_3EC4_si99[W_10_in] = W_2_do_si99[W_10_in];
   if ( L_337_in_2F3C_si99[W_10_in] >  0x0 )
   {
     L_339_do_32BC_si99[W_10_in] = NormalizeDouble(W_2_do_si99[W_10_in] / L_337_in_2F3C_si99[W_10_in],2);
   }
   else
   {
     L_339_do_32BC_si99[W_10_in] = 0.0;
   }
   L_344_do_4210_si99[W_10_in] = W_3_do_si99[W_10_in];
   if ( L_338_in_30FC_si99[W_10_in] >  0x0 )
   {
     L_340_do_3608_si99[W_10_in] = NormalizeDouble(W_3_do_si99[W_10_in] / L_338_in_30FC_si99[W_10_in],2);
   }
   else
   {
     L_340_do_3608_si99[W_10_in] = 0.0;
   }
 }
 }
//ccbsw_27 <<==--------   --------
 void ccbsw_28()
 {
  int       W_1_in;
  double    W_2_do;
  int       W_3_in;
  int       W_4_in;
  int       W_5_in;
  int       W_6_in;
  bool      W_7_bo;
  int       W_8_in;
  int       W_9_in;
  int       W_10_in;
  int       W_11_in;
//----- -----

 ccbsw_27(); 
 for (W_1_in = 0 ; W_1_in < L_375_in_5590 ; W_1_in ++)
 {
   W_2_do = L_343_do_3EC4_si99[W_1_in] ;
   W_3_in = 1 ;
   for (W_4_in = 0 ; W_4_in < L_375_in_5590 ; W_4_in ++)
   {
     if ( W_4_in == W_1_in || !(L_343_do_3EC4_si99[W_4_in]>W_2_do) )   continue;
     W_3_in ++;
     
   }
   L_350_in_5324_si99[W_1_in] = W_3_in;
 }
 for (W_5_in = 0 ; W_5_in < L_375_in_5590 ; W_5_in ++)
 {
   W_6_in = L_350_in_5324_si99[W_5_in] ;
   W_7_bo = true ;
   do
   {
     W_7_bo = false ;
     W_8_in = 0 ;
     if ( L_375_in_5590 <= 0 )   continue;
     
     for ( ; W_8_in < L_375_in_5590 ; W_8_in ++)
     {
       if ( W_8_in == W_5_in || L_350_in_5324_si99[W_8_in] != L_350_in_5324_si99[W_5_in] )   continue;
       L_350_in_5324_si99[W_8_in] ++;
       W_7_bo = true ;
       
     }
     
   }
   while(W_7_bo);
   
 }
 for (W_9_in = 0 ; W_9_in < L_375_in_5590 ; W_9_in ++)
 {
   L_348_do_4F40_si99[W_9_in] = 1.0;
 }
 for (W_10_in = 1 ; W_10_in <= L_375_in_5590 ; W_10_in ++)
 {
   for (W_11_in = 0 ; W_11_in < L_375_in_5590 ; W_11_in ++)
   {
     if ( L_350_in_5324_si99[W_11_in] == W_10_in )
     {
       L_333_in_2994_si99[W_10_in - 1] = W_11_in;
     }
   }
 }
 }
//ccbsw_28 <<==--------   --------
 void ccbsw_29()
 {
  int       W_1_in;
  double    W_2_do;
  int       W_3_in;
  int       W_4_in;
  int       W_5_in;
  int       W_6_in;
  bool      W_7_bo;
  int       W_8_in;
  int       W_9_in;
  int       W_10_in;
  int       W_11_in;
//----- -----

 ccbsw_27(); 
 for (W_1_in = 0 ; W_1_in < L_375_in_5590 ; W_1_in ++)
 {
   W_2_do = L_339_do_32BC_si99[W_1_in] ;
   W_3_in = 1 ;
   for (W_4_in = 0 ; W_4_in < L_375_in_5590 ; W_4_in ++)
   {
     if ( W_4_in == W_1_in || !(L_339_do_32BC_si99[W_4_in]>W_2_do) )   continue;
     W_3_in ++;
     
   }
   L_350_in_5324_si99[W_1_in] = W_3_in;
 }
 for (W_5_in = 0 ; W_5_in < L_375_in_5590 ; W_5_in ++)
 {
   W_6_in = L_350_in_5324_si99[W_5_in] ;
   W_7_bo = true ;
   do
   {
     W_7_bo = false ;
     W_8_in = 0 ;
     if ( L_375_in_5590 <= 0 )   continue;
     
     for ( ; W_8_in < L_375_in_5590 ; W_8_in ++)
     {
       if ( W_8_in == W_5_in || L_350_in_5324_si99[W_8_in] != L_350_in_5324_si99[W_5_in] )   continue;
       L_350_in_5324_si99[W_8_in] ++;
       W_7_bo = true ;
       
     }
     
   }
   while(W_7_bo);
   
 }
 for (W_9_in = 0 ; W_9_in < L_375_in_5590 ; W_9_in ++)
 {
   L_348_do_4F40_si99[W_9_in] = 1.0;
 }
 for (W_10_in = 1 ; W_10_in <= L_375_in_5590 ; W_10_in ++)
 {
   for (W_11_in = 0 ; W_11_in < L_375_in_5590 ; W_11_in ++)
   {
     if ( L_350_in_5324_si99[W_11_in] == W_10_in )
     {
       L_333_in_2994_si99[W_10_in - 1] = W_11_in;
     }
   }
 }
 }
//<<==ccbsw_29 <<==

