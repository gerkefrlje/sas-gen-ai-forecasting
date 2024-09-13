ods output OutInfo = _outInformation;

proc tsmodel data=&vf_libIn.."&vf_inData"n lead = &vf_lead.
            outobj=(	outfor  = &vf_libOut.."&vf_outFor"n
                        outStat = &vf_libOut.."&vf_outStat"n
                        outvarstatus=&vf_libOut..outvarstatus
                        pylog=&vf_libOut..pylog	)
            outarray = &vf_libOut..outarray
            outscalar = &vf_libOut..outscalar
            outlog = &vf_libOut.."&vf_outLog"n;
    id &vf_timeID interval = &vf_timeIDInterval setmissing = &vf_setMissing trimid = LEFT;
    %vf_varsTSMODEL;

    *define the by variables if exist;
    %if "&vf_byVars" ne "" %then %do;
       by &vf_byVars;
    %end;

    outarray ffm_fcst;
    outscalars _NAME_ $16 _MODEL_ $16 _MODELTYPE_ $16 _DEPTRANS_ $16 _SEASONAL_ _TREND_ _INPUTS_ _EVENTS_ _OUTLIERS_ _SOURCE_ $16;

    require tsm extlang;

    submit;

    API_KEY = '&_API_KEY';
    FINETUNE_STEPS = &_FINETUNE_STEPS.;
    FINETUNE_OSS = '&_FINETUNE_LOSS';

    declare object py(PYTHON3);
    declare object py(PYTHON3);
    rc = py.Initialize();

	rc = py.AddVariable(&vf_depVar,'ALIAS','TARGET');
    rc = py.AddVariable(&vf_timeID, 'ALIAS', 'TIMESTAMPS');
    rc = py.AddVariable(_LEAD_); /*pass the predefined variable to TF*/ 
    rc = py.AddVariable(API_KEY);
    rc = py.AddVariable(FINETUNE_STEPS);
    rc = py.AddVariable(FINETUNE_LOSS); 
    rc = py.AddVariable(ffm_fcst,"READONLY","NO","ARRAYRESIZE","YES","ALIAS",'PREDICT');
     * rc = py.AddEnvVariable('_TKMBPY_DEBUG_FILES_PATH', &log_folder);

	/* Packages needed for processing the call */
    rc = py.pushCodeLine("import json");
    rc = py.pushCodeLine("import re");
    rc = py.pushCodeLine("import ast");
    rc = py.pushCodeLine("import requests as req");
    rc = py.pushCodeLine("import pandas as pd");
	
	/* declare options for the model call */
    rc = py.pushCodeLine("url = 'https://api.nixtla.io/historic_forecast'");
    rc = py.pushCodeLine("fh = int(_LEAD_)");
    rc = py.pushCodeLine("authorization = f'Bearer {API_KEY}'");
    rc = py.pushCodeLine("finetune_steps = int(FINETUNE_STEPS)");
    rc = py.pushCodeLine("finetune_loss = FINETUNE_LOSS");
    rc = py.pushCodeLine("clean_ex_first = True");
    	
    /* turn the integer based SAS dates into pandas Timestamps */
	rc = py.pushCodeLine("sas_base_date = pd.Timestamp('1960-01-01')");
	rc = py.pushCodeLine("given_timestamps = TIMESTAMPS.tolist()[:-fh]");
	rc = py.pushCodeLine("pandas_dates = [sas_base_date + pd.Timedelta(days=int_date) for int_date in given_timestamps]");
    rc = py.pushCodeLine("freq = pd.infer_freq(pandas_dates)");

    /* generate dictionary which will be passed to the model */
    rc = py.pushCodeLine("values = TARGET.tolist()");
    rc = py.pushCodeLine("forecast_input = {pandas_dates[i].strftime('%Y-%m-%d'): values[i] for i in range(len(pandas_dates))}");
    
    rc = py.pushCodeLine("payload = {");
    rc = py.pushCodeLine("	'model': 'timegpt-1',");
    rc = py.pushCodeLine("	'freq': freq,");
    rc = py.pushCodeLine("	'clean_ex_first': clean_ex_first,");
    rc = py.pushCodeLine("	'y': forecast_input");
    rc = py.pushCodeLine("}");
    rc = py.pushCodeLine("headers = {");
	rc = py.pushCodeLine("'Content-Type': 'application/json',");
    rc = py.pushCodeLine("  'accept': 'application/json',");
    rc = py.pushCodeLine("  'authorization': authorization");
    rc = py.pushCodeLine("}");

    rc = py.pushCodeLine("resp = req.post(url, headers=headers, json=payload)");
    
    rc = py.pushCodeLine("resp_dict = ast.literal_eval(resp.text)");

    rc = py.pushCodeLine("historic_forecast = resp_dict['data']['value']");
    
    rc = py.pushCodeLine("url = 'https://api.nixtla.io/forecast'");

    rc = py.pushCodeLine("payload = {");
    rc = py.pushCodeLine("	'model': 'timegpt-1',");
    rc = py.pushCodeLine("	'freq': freq,");
    rc = py.pushCodeLine("	'fh': fh,");
    rc = py.pushCodeLine("	'clean_ex_first': clean_ex_first,");
    rc = py.pushCodeLine("	'y': forecast_input,");
    rc = py.pushCodeLine("	'finetune_steps': 10,");
    rc = py.pushCodeLine("	'finetune_loss': 'default'");
    rc = py.pushCodeLine("}");
    rc = py.pushCodeLine("headers = {");
	rc = py.pushCodeLine("'Content-Type': 'application/json',");
    rc = py.pushCodeLine("  'accept': 'application/json',");
    rc = py.pushCodeLine("  'authorization': authorization");
    rc = py.pushCodeLine("}");

    rc = py.pushCodeLine("resp = req.post(url, headers=headers, json=payload)");
    
    rc = py.pushCodeLine("resp_dict = ast.literal_eval(resp.text)");

    rc = py.pushCodeLine("forecast = resp_dict['data']['value']");

    rc = py.pushCodeLine("prediction = [*historic_forecast, *forecast]");

    rc = py.pushCodeLine("buffer_length = len(TARGET) - len(prediction)");
    rc = py.pushCodeLine("buffer = [np.nan] * buffer_length");

    rc = py.pushCodeLine("prediction = buffer + prediction");

	rc = py.pushCodeLine("PREDICT = prediction");

    rc = py.Run();

    declare object pylog(OUTEXTLOG);
	rc = pylog.Collect(py, 'EXECUTION');

	declare object outvarstatus(OUTEXTVARSTATUS);
	rc = outvarstatus.Collect(py);

	declare object pyExmSpec(EXMSPEC);
	rc = pyExmSpec.open();
	rc = pyExmSpec.setOption('METHOD', 'PERFECT');
	rc = pyExmSpec.setOption('NLAGPCT', 0);
	rc = pyExmSpec.setOption('PREDICT', 'ffm_fcst');
	rc = pyExmSpec.close();

    declare object tsm(tsm);
	
    rc = tsm.Initialize(pyExmSpec);
    rc = tsm.AddExternal(ffm_fcst, 'PREDICT');
	rc = tsm.SetY(&vf_depVar);
	rc = tsm.SetOption('LEAD', &vf_lead);

    rc = tsm.Run();

	declare object outFor(tsmFor);
	declare object outStat(tsmStat);

	rc = outFor.collect(tsm);
	rc = outFor.SetOption('MODELNAME', 'Nixtla');
	rc = outStat.collect(tsm);
	rc = outStat.SetOption('MODELNAME', 'Nixtla');

    _NAME_ = vname(&vf_depVar);
	_MODEL_ = "ffmModel";
	_MODELTYPE_ = MODEL_SELECTION;
	_DEPTRANS_ = "NONE";
	_SEASONAL_ = 1;
	_TREND_ = 1;
	_INPUTS_ = 0;
	_EVENTS_ = 0;
	_OUTLIERS_ = 0;
	_SOURCE_ = "TSM.EXMSPEC";

	endsubmit;
run;

/* Manually create OUTMODELINFO. Necessary since we use TSM instead */
/* of ATSM and it does not generate this table automatically.       */
data &vf_libOut.."&vf_outModelInfo"n;
	retain _NAME_ _MODEL_ _MODELTYPE_ _DEPTRANS_ _SEASONAL_ _TREND_ _INPUTS_ _EVENTS_ _OUTLIERS_ _SOURCE_ _STATUS_;
	set &vf_libOut..outscalar;
run;

/* ALso, the OUTSTAT table is missing the _SELECT_ column. */
data &vf_libOut.."&vf_outStat"n;
    set &vf_libOut.."&vf_outStat"n;
    _SELECT_ = 'forecast';
run;

/* Generate outinformation CAS table */
data &vf_libOut.."&vf_outInformation"n;
    set work._outInformation;
run;
