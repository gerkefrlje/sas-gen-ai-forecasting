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

    outarray ffm_fcst ffm_lfcst ffm_ufcst ffm_err ffm_stderr;
    outscalars _NAME_ $16 _MODEL_ $16 _MODELTYPE_ $16 _DEPTRANS_ $16 _SEASONAL_ _TREND_ _INPUTS_ _EVENTS_ _OUTLIERS_ _SOURCE_ $16;

    require tsm extlang;

    submit;

    MODEL_SELECTION = '&_model_selection';

    CHRONOS_DOMAIN = '&_model_domain';          /* domain of the model                  */
    CHRONOS_ENDPOINT = '&_model_endpoint';      /* endpoint of the chronos model        */
    CHRONOS_URL = CHRONOS_DOMAIN || CHRONOS_ENDPOINT;

    NUM_SAMPLES = &_num_samples.;               /* increases performance and runtime    */
    TEMPERATURE = &_temperature.;               /* token generation temperature         */
    TOP_K = &_top_k.;                           /* token generation Top-K               */
    TOP_P = &_top_p.;                           /* token generation Top-p               */

    declare object py(PYTHON3);
    rc = py.Initialize();

	rc = py.AddVariable(&vf_depVar,'ALIAS','TARGET') ;
    rc = py.AddVariable(&vf_timeID, 'ALIAS', 'ds');
    rc = py.AddVariable(CHRONOS_URL);
    rc = py.AddVariable(_LEAD_); /*pass the predefined variable to TF*/ 
    rc = py.AddVariable(NUM_SAMPLES);
    rc = py.AddVariable(TEMPERATURE);
    rc = py.AddVariable(TOP_K);
    rc = py.AddVariable(TOP_P);
    rc = py.AddVariable(ffm_fcst,"READONLY","NO","ARRAYRESIZE","YES","ALIAS",'PREDICT');
	rc = py.AddVariable(ffm_lfcst,"READONLY","NO","ARRAYRESIZE","YES","ALIAS",'LOWER');
	rc = py.AddVariable(ffm_ufcst,"READONLY","NO","ARRAYRESIZE","YES","ALIAS",'UPPER');
	rc = py.AddVariable(ffm_err,"READONLY","NO","ARRAYRESIZE","YES","ALIAS",'ERR');
	rc = py.AddVariable(ffm_stderr,"READONLY","NO","ARRAYRESIZE","YES","ALIAS",'STDERR');
     * rc = py.AddEnvVariable('_TKMBPY_DEBUG_FILES_PATH', &log_folder);

	/* Packages needed for processing the call */
    rc = py.pushCodeLine("import json");
    rc = py.pushCodeLine("import math");
    rc = py.pushCodeLine("import requests as req");
    rc = py.pushCodeLine("import numpy as np");
	
	/* Import the variables set outside of the python code */
    rc = py.pushCodeLine("url = CHRONOS_URL");
    rc = py.pushCodeLine("prediction_length = int(_LEAD_)");
    rc = py.pushCodeLine("num_samples = int(NUM_SAMPLES)");
    rc = py.pushCodeLine("temperature = float(TEMPERATURE)");
    rc = py.pushCodeLine("top_k = int(TOP_K)");
    rc = py.pushCodeLine("top_p = float(TOP_P)");
    
    /****************************************************************** */
    /* First, to get some fit statistics for the model, a prediction    */
    /* is called on the last _LEAD_ points of the existing data.        */
    /* Afterwards, it is run for the time window after the last given.  */
    /****************************************************************** */

    /* Set the options for the model API call */
    rc = py.pushCodeLine("payload = json.dumps({");
    rc = py.pushCodeLine("	'prediction_length': prediction_length,");
    rc = py.pushCodeLine("	'num_samples': num_samples,");
    rc = py.pushCodeLine("	'temperature': temperature,");
    rc = py.pushCodeLine("	'top_k': top_k,");
    rc = py.pushCodeLine("	'top_p': top_p,");
    rc = py.pushCodeLine("	'data': TARGET.tolist()[:-prediction_length]");
    rc = py.pushCodeLine("})");
    rc = py.pushCodeLine("headers = {'Content-Type': 'application/json'}");

    /* The call will return a string with 3 (Median Forecast and limits of the 80% prediction interval) */
	/* by X values, where X is the prediction length. The values are separated by commas.               */
    rc = py.pushCodeLine("resp = req.post(url, headers=headers, data=payload, verify=False)");
    
	/* Process the resulting values into workable objects */
    rc = py.pushCodeLine("forecast_validation = resp.text.splitlines()");
    rc = py.pushCodeLine("forecast_validation_values = np.genfromtxt(forecast_validation, delimiter=',', skip_header=1)");

    /* Repeat the above steps for the forecast horizon. */
    rc = py.pushCodeLine("payload = json.dumps({");
    rc = py.pushCodeLine("	'prediction_length': prediction_length,");
    rc = py.pushCodeLine("	'num_samples': num_samples,");
    rc = py.pushCodeLine("	'temperature': temperature,");
    rc = py.pushCodeLine("	'top_k': top_k,");
    rc = py.pushCodeLine("	'top_p': top_p,");
    rc = py.pushCodeLine("	'data': TARGET.tolist()");
    rc = py.pushCodeLine("})");
    rc = py.pushCodeLine("headers = {'Content-Type': 'application/json'}");

    rc = py.pushCodeLine("resp = req.post(url, headers=headers, data=payload, verify=False)");
    
    rc = py.pushCodeLine("forecast = resp.text.splitlines()");
    rc = py.pushCodeLine("forecast_header = forecast[0].split(',')");
    rc = py.pushCodeLine("forecast_values = np.genfromtxt(forecast, delimiter=',', skip_header=1)");

	/* Generate an empty numpy ndarray so that the predicted values are appended at the right index */
    rc = py.pushCodeLine("prediction = np.empty(TARGET.shape[0] - (2 * prediction_length))");
    rc = py.pushCodeLine("prediction[:] = np.nan");

	/* Repeat for the lower and upper prediction interval borders and the standard error */
    rc = py.pushCodeLine("lower = np.empty(TARGET.shape[0] - (2 * prediction_length))");
    rc = py.pushCodeLine("lower[:] = np.nan");
	rc = py.pushCodeLine("upper = np.empty(TARGET.shape[0] - (2 * prediction_length))");
    rc = py.pushCodeLine("upper[:] = np.nan");

    
    rc = py.pushCodeLine("prediction = np.concatenate((prediction, forecast_validation_values[:, forecast_header.index('median')]))");
    rc = py.pushCodeLine("prediction = np.concatenate((prediction, forecast_values[:, forecast_header.index('median')]))");

    
    rc = py.pushCodeLine("lower = np.concatenate((lower, forecast_validation_values[:, forecast_header.index('low')]))");
    rc = py.pushCodeLine("lower = np.concatenate((lower, forecast_values[:, forecast_header.index('low')]))");
	
    
    rc = py.pushCodeLine("upper = np.concatenate((upper, forecast_validation_values[:, forecast_header.index('high')]))");
    rc = py.pushCodeLine("upper = np.concatenate((upper, forecast_values[:, forecast_header.index('high')]))");

    /* ALso create arrays for the prediction error and standard error of the interval */
    rc = py.pushCodeLine("err = TARGET - prediction");

	rc = py.pushCodeLine("interval_width = upper - lower");
	rc = py.pushCodeLine("z_score = 1.28");
	rc = py.pushCodeLine("stderr = interval_width / (2 * z_score)");

    /* Map the arrays created in the python code to the SAS Series */
	rc = py.pushCodeLine("PREDICT = prediction");
	rc = py.pushCodeLine("LOWER = lower");
	rc = py.pushCodeLine("UPPER = upper");
	rc = py.pushCodeLine("ERR = err");
	rc = py.pushCodeLine("STDERR = stderr");

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
	rc = pyExmSpec.setOption('LOWER', 'ffm_lfcst');
	rc = pyExmSpec.setOption('UPPER', 'ffm_ufcst');
	rc = pyExmSpec.setOption('STDERR', 'ffm_stderr');
	rc = pyExmSpec.close();

    declare object tsm(tsm);

	
    rc = tsm.Initialize(pyExmSpec);
    rc = tsm.AddExternal(ffm_fcst, 'PREDICT');
	rc = tsm.AddExternal(ffm_lfcst, 'LOWER');
	rc = tsm.AddExternal(ffm_ufcst, 'UPPER');
    rc = tsm.AddExternal(ffm_err, 'ERROR');
	rc = tsm.AddExternal(ffm_stderr, 'STDERR');
	rc = tsm.SetY(&vf_depVar);
	rc = tsm.SetOption('LEAD', &vf_lead);
	rc = tsm.SetOption('ALPHA', 0.2);

    rc = tsm.Run();

	declare object outFor(tsmFor);
	declare object outStat(tsmStat);

	rc = outFor.collect(tsm);
	rc = outFor.SetOption('MODELNAME', 'Chronos');
	rc = outStat.collect(tsm);
	rc = outStat.SetOption('MODELNAME', 'Chronos');

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
