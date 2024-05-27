/*----------------------------------------------------------------------+
 | LSTM TensorFlow Forecasting with the EXTLANG Package and TensorFlow 
 | 
 | Any questions, please contact:
 |
 | Taiyeong.Lee@sas.com for TensorFlow python code 
 | Javier.Delgado@sas.com for the EXTLANG package 
 | Iman.VasheghaniFarahani@sas.com for Visual Forecasting pluggable code 
+------------------------------------------------------------------------*/

ods output OutInfo = _outInformation;

proc tsmodel data=&vf_libIn.."&vf_inData"n lead = &vf_lead.
            outobj=(outfor  = &vf_libOut.."&vf_outFor"n
            outSelect = &vf_libOut.."&vf_outSelect"n
            outStat = &vf_libOut.."&vf_outStat"n
            outmodelinfo = &vf_libOut.."&vf_outModelInfo"n
            outvarstatus=&vf_libOut..outvarstatus
            pylog=&vf_libOut..pylog)
            outarray = &vf_libOut..outarray
            outlog = &vf_libOut.."&vf_outLog"n;
    id &vf_timeID interval = &vf_timeIDInterval setmissing = &vf_setMissing trimid = LEFT;
    %vf_varsTSMODEL;

    *define the by variables if exist;
    %if "&vf_byVars" ne "" %then %do;
       by &vf_byVars;
    %end;
    
    outarray tf_fcst;
    require atsm tsm extlang;
    submit;
    /* specify common options  */
    NINPUT = &_NINPUT;                      /* input window width, time_steps     */ 
    NHOLDOUT = &_holdoutSampleSize;         /* holdout sample size                */

    /* some TensorFlow Keras model options */

    MAXEPOCH = &_MAXEPOCH.;                 /* maximum number of epochs           */
    LEARNING_RATE = &_LEARNING_RATE.;       /* learning rate for optimizer        */ 
    BATCH_SIZE = &_BATCH_SIZE.;             /* minibatch size                     */
    SEED = &_SEED.;                         /* seed for random number             */ 
    ES_MIN_DELTA = &_ES_MIN_DELTA;          /* early stopping delta parameter     */
    ES_PATIENCE = &_ES_PATIENCE.;           /* early stopping stagnation parameter*/
	NUM_LSTM_LAYER = &_NUM_LSTM_LAYER.;		/* maximum number of LSTM layers	  */

    declare object py(PYTHON3); 
    rc = py.Initialize();
    rc = py.AddVariable(&vf_depVar,'ALIAS','TARGET') ;
    rc = py.AddVariable(&vf_timeID);
    rc = py.AddVariable(NINPUT);
    rc = py.AddVariable(NHOLDOUT);
    rc = py.AddVariable(_LEAD_); /*pass the predefined variable to TF*/ 
    rc = py.AddVariable(MAXEPOCH);
    rc = py.AddVariable(LEARNING_RATE);
    rc = py.AddVariable(BATCH_SIZE);
    rc = py.AddVariable(SEED);
    rc = py.AddVariable(ES_MIN_DELTA);
    rc = py.AddVariable(ES_PATIENCE);
	rc = py.AddVariable(NUM_LSTM_LAYER);
    rc = py.AddVariable(tf_fcst,"READONLY","NO","ARRAYRESIZE","YES","ALIAS",'PREDICT'); 
    * rc = py.AddEnvVariable('_TKMBPY_DEBUG_FILES_PATH', &log_folder);

    /* The beginning of TensorFlow python code */
    rc = py.PushCodeLine("import numpy as np");
    rc = py.PushCodeLine("import tensorflow as tf");
    rc = py.PushCodeLine("from tensorflow import keras");
    rc = py.PushCodeLine("from sklearn.preprocessing import StandardScaler");
    rc = py.PushCodeLine("from tensorflow.keras.callbacks import EarlyStopping");
    rc = py.PushCodeLine("time_steps = int(NINPUT)");
    rc = py.PushCodeLine("lead = int(_LEAD_)");
    rc = py.PushCodeLine("nholdout = int(NHOLDOUT)");
    rc = py.PushCodeLine("maxepoch = int(MAXEPOCH)");
    rc = py.PushCodeLine("learning_rate = float(LEARNING_RATE)");
    rc = py.PushCodeLine("batch_size = int(BATCH_SIZE)");
    rc = py.PushCodeLine("es_min_delta = float(ES_MIN_DELTA)");
    rc = py.PushCodeLine("es_patience = int(ES_PATIENCE)");
    rc = py.PushCodeLine("seed = int(SEED)");
    rc = py.PushCodeLine("np.random.seed(seed)");
    rc = py.PushCodeLine("tf.random.set_seed(seed)");
    rc = py.PushCodeLine("x = TARGET[0:len(TARGET)-lead]");
    rc = py.PushCodeLine("x = np.reshape(x, (x.shape[0], 1))");
    rc = py.PushCodeLine("date = np.reshape(DATE, (DATE.shape[0], 1))");
    rc = py.PushCodeLine("scaler = StandardScaler()");
    rc = py.PushCodeLine("std_x  = scaler.fit_transform(x)");
    rc = py.PushCodeLine("inputdata, targetdata = [], []");
    rc = py.PushCodeLine("for i in range(len(std_x) - time_steps):");
    rc = py.PushCodeLine("  inputdata.append(std_x[i: (i+time_steps),])");
    rc = py.PushCodeLine("  targetdata.append(std_x[i+time_steps,])");
    rc = py.PushCodeLine("inputdata  = np.array(inputdata)");
    rc = py.PushCodeLine("targetdata = np.array(targetdata)");
    rc = py.PushCodeLine("datalength = len(inputdata)");
    rc = py.PushCodeLine("ntrain = datalength - nholdout");
    rc = py.PushCodeLine("xtrain, ytrain = inputdata[0:ntrain, ], targetdata[0:ntrain,]");
    rc = py.PushCodeLine("xvalid, yvalid = inputdata[ntrain:, ], targetdata[ntrain:,]");
    rc = py.PushCodeLine("model = keras.Sequential()");
    rc = py.PushCodeLine("model.add(keras.layers.LSTM(NUM_LSTM_LAYER, input_shape=(xtrain.shape[1], xtrain.shape[2])))");
    rc = py.PushCodeLine("model.add(keras.layers.Dense(1))");
    rc = py.PushCodeLine("early_stopping = EarlyStopping(monitor='val_loss', min_delta=es_min_delta, patience=es_patience, restore_best_weights=True)");
    rc = py.PushCodeLine("model.compile(loss='mean_squared_error',optimizer=keras.optimizers.Adam(learning_rate))");
    rc = py.PushCodeLine("fit_history = model.fit(x=xtrain, y=ytrain, validation_data= (xvalid, yvalid),epochs=maxepoch, batch_size=batch_size, shuffle=False, callbacks=[early_stopping])");
    rc = py.PushCodeLine("std_pred_train = model.predict(xtrain)");
    rc = py.PushCodeLine("std_pred_valid = model.predict(xvalid)");
    rc = py.PushCodeLine("pred_train = scaler.inverse_transform(std_pred_train)");
    rc = py.PushCodeLine("pred_valid = scaler.inverse_transform(std_pred_valid)");
    rc = py.PushCodeLine("init_window_pred = np.full([time_steps,1], np.nan)");
    rc = py.PushCodeLine("pred = np.concatenate((init_window_pred, pred_train, pred_valid), axis=0)");
    rc = py.PushCodeLine("if nholdout > 0:");
    rc = py.PushCodeLine("	length = len(xvalid)");
    rc = py.PushCodeLine("	ylast = yvalid[length-1:length]");
    rc = py.PushCodeLine("	xlast = xvalid[length-1:length]");
    rc = py.PushCodeLine("else:");
    rc = py.PushCodeLine("	length = len(xtrain)");
    rc = py.PushCodeLine("	xlast = xtrain[length-1:length]");
    rc = py.PushCodeLine("	ylast = ytrain[length-1:length]");
    rc = py.PushCodeLine("xnew = np.copy(xlast)");
    rc = py.PushCodeLine("for i in range(time_steps):");
    rc = py.PushCodeLine("	if(i < time_steps-1):");
    rc = py.PushCodeLine("		xnew.itemset((0,i,0), xlast.item(0,i+1,0))");
    rc = py.PushCodeLine("	if(i == (time_steps-1)):");
    rc = py.PushCodeLine("		xnew.itemset((0,i,0), ylast.item(0,0))");
    rc = py.PushCodeLine("std_fcst = list()");
    rc = py.PushCodeLine("for k in range(lead):");
    rc = py.PushCodeLine("	std_pred_xlast = model.predict(xlast)");
    rc = py.PushCodeLine("	std_fcst.append(std_pred_xlast[0:1,0])");
    rc = py.PushCodeLine("	xnew = np.copy(xlast)");
    rc = py.PushCodeLine("	for i in range(time_steps):");
    rc = py.PushCodeLine("		if(i < time_steps-1):");
    rc = py.PushCodeLine("			xnew.itemset((0,i,0), xlast.item(0,i+1,0))");
    rc = py.PushCodeLine("		if(i == (time_steps-1)):");
    rc = py.PushCodeLine("			xnew.itemset((0,i,0), ylast.item(0,0))");
    rc = py.PushCodeLine("	xlast = np.copy(xnew)");
    rc = py.PushCodeLine("std_fcstarray = np.array(std_fcst)");
    rc = py.PushCodeLine("forecast = scaler.inverse_transform(std_fcstarray)");
    rc = py.PushCodeLine("pred_all = np.concatenate((pred, forecast), axis=0)");
    rc = py.PushCodeLine("pred_all = np.reshape(pred_all, pred_all.shape[0])");
    rc = py.PushCodeLine("PREDICT = pred_all");
    /* The ending of TF python code */
    rc = py.Run();  
    /* Store the execution and resource usage statistics logs */
    declare object pylog(OUTEXTLOG);
    rc = pylog.Collect(py,'EXECUTION');
    declare object outvarstatus(OUTEXTVARSTATUS);
    rc = outvarstatus.Collect(py);
    declare object pyExmSpec(EXMSPEC);
    rc = pyExmSpec.open();
    rc = pyExmSpec.setOption('METHOD','PERFECT');
    rc = pyExmSpec.setOption('NLAGPCT',0);
    rc = pyExmSpec.setOption('PREDICT','tf_fcst');
    rc = pyExmSpec.close();
    
    declare object dataFrame(tsdf);
    declare object diagnose(diagnose);
    declare object diagSpec(diagspec);
    declare object inselect(selspec); 
    declare object forecast(foreng);
    
    /*initialize the tsdf object and assign the time series roles: setup dependent and independent variables*/
    rc = dataFrame.initialize();
    rc = dataFrame.AddSeries(tf_fcst);
    rc = dataFrame.addY(&vf_depVar);
    
    /*Run model selection and forecast*/                     
    rc = inselect.Open(1); 
    rc = inselect.AddFrom(pyExmSpec);
    rc = inselect.close(); 
    
    /*initialize the foreng object with the diagnose result and run model selecting and generate forecasts;*/         
    rc = forecast.initialize(dataFrame);
    rc = forecast.AddFrom(inselect);
    rc = forecast.setOption('lead', &vf_lead);
    rc = forecast.setOption('back', &vf_back);
    
    %if "&vf_allowNegativeForecasts" eq "FALSE" %then %do;
        rc = forecast.setOption('fcst.bd.lower',0);
    %end;
    rc = forecast.Run();

    /*collect forecast results*/
    declare object outFor(outFor);
    declare object outSelect(outSelect);
    declare object outStat(outStat);
    declare object outModelInfo(outModelInfo);

    /*collect the forecast and statistic-of-fit from the forgen object run results; */
    rc = outFor.collect(forecast);
    rc = outSelect.collect(forecast); 
    rc = outStat.collect(forecast);  
    rc = outModelInfo.collect(forecast);
endsubmit;
run;

/* generate outinformation CAS table */
data &vf_libOut.."&vf_outInformation"n;
    set work._outInformation;
run;
