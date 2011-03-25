classdef dotsStimulus < baseStimulus
	%DOTSSTIMULUS single coherent dots stimulus, inherits from baseStimulus
	%   The current properties are:
	
	properties %--------------------PUBLIC PROPERTIES----------%
		family = 'dots'
		type = 'simple'
		density = 35;
		nDots = 100 % number of dots
		colourType = 'randomBW'
		dotSize  = 0.05  % width of dot (deg)
		coherence = 0.5
		kill      = 0.2 % fraction of dots to kill each frame  (limited lifetime)
		dotType = 1
		mask = true
		maskColour = [0.5 0.5 0.5 0.5]
	end
	
	properties (SetAccess = private, GetAccess = public)
		xy
		dxdy
		colours
	end
	properties (SetAccess = private, GetAccess = private)
		fieldScale = 1.1
		fieldSize
		maskTexture
		maskRect
		srcMode = 'GL_ONE'
		dstMode = 'GL_ZERO'
		antiAlias = 4
		rDots
		nDotsMax = 5000
		angles
		dSize
		fps = 60
		dxs
		dys
		allowedProperties='^(type|nDots|dotSize|colourType|coherence|dotType|kill|mask)$';
		ignoreProperties='xy|dxdy|colours|mask|maskTexture|colourType'
	end
	
	%=======================================================================
	methods %------------------PUBLIC METHODS
		%=======================================================================
		
		% ===================================================================
		%> @brief Class constructor
		%>
		%> More detailed description of what the constructor does.
		%>
		%> @param args are passed as a structure of properties which is
		%> parsed.
		%> @return instance of class.
		% ===================================================================
		function obj = dotsStimulus(args)
			%Initialise for superclass, stops a noargs error
			if nargin == 0
				args.family = 'dots';
			end
			obj=obj@baseStimulus(args); %we call the superclass constructor first
			%check we are a grating
			if ~strcmpi(obj.family,'dots')
				error('Sorry, you are trying to call a dotsStimulus with a family other than dots');
			end
			%start to build our parameters
			if nargin>0 && isstruct(args)
				fnames = fieldnames(args); %find our argument names
				for i=1:length(fnames);
					if regexp(fnames{i},obj.allowedProperties) %only set if allowed property
						obj.salutation(fnames{i},'Configuring setting in dotsStimulus constructor');
						obj.(fnames{i})=args.(fnames{i}); %we set up the properies from the arguments as a structure
					end
				end
			end
			obj.ignoreProperties = ['^(' obj.ignorePropertiesBase '|' obj.ignoreProperties ')$'];
			obj.salutation('constructor','Dots Stimulus initialisation complete');
		end
		
		% ===================================================================
		%> @brief Setup an structure for runExperiment
		%>
		%> @param rE runExperiment object for reference
		%> @return
		% ===================================================================
		function setup(obj,rE)
			
			if exist('rE','var')
				obj.ppd=rE.ppd;
				obj.ifi=rE.screenVals.ifi;
				obj.xCenter=rE.xCenter;
				obj.yCenter=rE.yCenter;
				obj.win=rE.win;
				obj.srcMode=rE.srcMode;
				obj.dstMode=rE.dstMode;
				obj.backgroundColour = rE.backgroundColour;
			end
			
			fn = fieldnames(dotsStimulus);
			for j=1:length(fn)
				if isempty(obj.findprop([fn{j} 'Out'])) && isempty(regexp(fn{j},obj.ignoreProperties, 'once')) %create a temporary dynamic property
					p=obj.addprop([fn{j} 'Out']);
					p.Transient = true;%p.Hidden = true;
					if strcmp(fn{j},'size');p.SetMethod = @setsizeOut;end
					if strcmp(fn{j},'dotSize');p.SetMethod = @setdotSizeOut;end
					if strcmp(fn{j},'xPosition');p.SetMethod = @setxPositionOut;end
					if strcmp(fn{j},'yPosition');p.SetMethod = @setyPositionOut;end
				end
				if isempty(regexp(fn{j},obj.ignoreProperties, 'once'))
					obj.([fn{j} 'Out']) = obj.(fn{j}); %copy our property value to our tempory copy
				end
			end
			
			if isempty(obj.findprop('doDots'));p=obj.addprop('doDots');p.Transient = true;end
			if isempty(obj.findprop('doMotion'));p=obj.addprop('doMotion');p.Transient = true;end
			if isempty(obj.findprop('doDrift'));p=obj.addprop('doDrift');p.Transient = true;end
			if isempty(obj.findprop('doFlash'));p=obj.addprop('doFlash');p.Transient = true;end
			obj.doDots = [];
			obj.doMotion = [];
			obj.doDrift = [];
			obj.doFlash = [];
			
			if isempty(obj.findprop('xTmp'));p=obj.addprop('xTmp');p.Transient = true;end
			if isempty(obj.findprop('yTmp'));p=obj.addprop('yTmp');p.Transient = true;end
			obj.xTmp = obj.xPositionOut; %xTmp and yTmp are temporary position stores.
			obj.yTmp = obj.yPositionOut;
			
			wrect = SetRect(0, 0, obj.fieldSize, obj.fieldSize);
			mrect = SetRect(0, 0, obj.sizeOut, obj.sizeOut);
			mrect = CenterRect(mrect,wrect);
			bg = [obj.backgroundColour(1:3) 1];
			obj.maskTexture = Screen('OpenOffscreenwindow', obj.win, bg, wrect);
			Screen('FillOval', obj.maskTexture, obj.maskColour, mrect);
			obj.maskRect = CenterRectOnPointd(wrect,obj.xPositionOut,obj.yPositionOut);
			
			%make our dot colours
			switch obj.colourType
				case 'random'
					obj.colours = rand(4,obj.nDots);
					obj.colours(4,:) = obj.alpha;
				case 'randomN'
					obj.colours = randn(4,obj.nDots);
					obj.colours(4,:) = obj.alpha;
				case 'randomBW'
					obj.colours=zeros(4,obj.nDots);
					for i = 1:obj.nDots
						obj.colours(:,i)=rand;
					end
					obj.colours(4,:)=obj.alpha;
				case 'binary'
					obj.colours=zeros(4,obj.nDots);
					rix = round(rand(obj.nDots,1)) > 0;
					obj.colours(:,rix) = 1;
					obj.colours(4,:)=obj.alpha; %set the alpha level
				otherwise
					obj.colours=obj.colour;
					obj.colours(4)=obj.alpha;
			end
			
			obj.updateDots;
			
		end
		
		% ===================================================================
		%> @brief Update the dots per frame and wrap dots that exceed the size
		%>
		% ===================================================================
		function updateDots(obj)
			%sort out our angles and percent incoherent
			obj.angles = ones(obj.nDots,1) .* obj.angleOut;
			obj.rDots=obj.nDots-floor(obj.nDots*(obj.coherenceOut));
			if obj.rDots>0
				obj.angles(1:obj.rDots)= obj.r2d((2*pi).*rand(1,obj.rDots));
				obj.angles = Shuffle(obj.angles); %if we don't shuffle them, all coherent dots show on top!
			end
			%calculate positions and vector offsets
			obj.xy = obj.sizeOut .* rand(2,obj.nDots);
			obj.xy = obj.xy - obj.sizeOut/2; %so we are centered for -xy to +xy
			[obj.dxs, obj.dys] = obj.updatePosition(repmat(obj.delta,size(obj.angles)),obj.angles);
			obj.dxdy=[obj.dxs';obj.dys'];
		end
		
		% ===================================================================
		%> @brief Update an structure for runExperiment
		%>
		%> @param rE runExperiment object for reference
		%> @return stimulus structure.
		% ===================================================================
		function update(obj)
			obj.updateDots;
		end
		
		% ===================================================================
		%> @brief Draw an structure for runExperiment
		%>
		%> @param rE runExperiment object for reference
		%> @return stimulus structure.
		% ===================================================================
		function draw(obj)
			if obj.isVisible == true
				if obj.mask == true
					Screen('BlendFunction', obj.win, GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
					Screen('DrawDots', obj.win,obj.xy,obj.dotSizeOut,obj.colours,...
						[obj.xPositionOut obj.yPositionOut],obj.dotTypeOut);
					Screen('DrawTexture', obj.win, obj.maskTexture, [], obj.maskRect, [], [], [], [], 0);
					Screen('BlendFunction', obj.win, obj.srcMode, obj.dstMode);
				else
					Screen('DrawDots',obj.win,obj.xy,obj.dotSizeOut,obj.colours,...
						[obj.xPositionOut obj.yPositionOut],obj.dotTypeOut);
				end
			end
		end
		
		% ===================================================================
		%> @brief Animate an structure for runExperiment
		%>
		%> @param rE runExperiment object for reference
		%> @return stimulus structure.
		% ===================================================================
		function animate(obj)
			obj.xy = obj.xy + obj.dxdy; %increment position
			fix = find(obj.xy > obj.sizeOut/2); %cull positive
			obj.xy(fix) = obj.xy(fix) - obj.sizeOut;
			fix = find(obj.xy < -obj.sizeOut/2);  %cull negative
			obj.xy(fix) = obj.xy(fix) + obj.sizeOut;
		end
		
		% ===================================================================
		%> @brief Reset an structure for runExperiment
		%>
		%> @param rE runExperiment object for reference
		%> @return stimulus structure.
		% ===================================================================
		function reset(obj)
			obj.removeTmpProperties;
			obj.angles = [];
			obj.xy = [];
			obj.dxs = [];
			obj.dys = [];
			obj.dxdy = [];
			obj.colours = [];
		end
		
		% ===================================================================
		%> @brief Reset an structure for runExperiment
		%>
		%> @param rE runExperiment object for reference
		%> @return stimulus structure.
		% ===================================================================
		function run(obj)
			
			try
				obj.dSize = obj.dotSize * obj.ppd;
				obj.setup;
				Screen('Preference', 'SkipSyncTests', 2);
				Screen('Preference', 'VisualDebugLevel', 0);
				PsychImaging('PrepareConfiguration');
				PsychImaging('AddTask', 'General', 'FloatingPoint32BitIfPossible');
				PsychImaging('AddTask', 'General', 'UseFastOffscreenWindows');
				PsychImaging('AddTask', 'General', 'NormalizedHighresColorRange');
				[w, rect]=PsychImaging('OpenWindow', 0, 0.5,[1 1 801 601], [], 2,[],obj.antiAlias);
				[center(1), center(2)] = RectCenter(rect);
				Screen('BlendFunction', w, GL_ONE, GL_ZERO);
				
				obj.fps=Screen('FrameRate',w);      % frames per second
				obj.ifi=Screen('GetFlipInterval', w);
				if obj.fps==0
					obj.fps=1/obj.ifi;
				end;
				
				wrect = SetRect(0, 0, obj.fieldSize, obj.fieldSize);
				%wrect = CenterRectOnPointd(wrect,center(1),center(2));
				orect = SetRect(0, 0, obj.sizeOut, obj.sizeOut);
				orect = CenterRect(orect,wrect);
				obj.maskTexture = Screen('OpenOffscreenwindow', w, [0.55 0.5 0.5 1], wrect);
				Screen('FillOval', obj.maskTexture, [0.5 0.5 0.5 0.5], orect);
				outrect = CenterRectOnPointd(wrect,center(1),center(2));
				
				vbl=Screen('Flip', w);
				while 1
					Screen('BlendFunction', w, GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
					Screen('DrawDots', w, obj.xy, obj.dSize, obj.colours, center, obj.dotType);  % change 1 to 0 to draw square dots
					Screen('DrawTexture', w, obj.maskTexture, [], outrect, [], [], [], [], 0);
					%Screen('DrawTexture',obj.win,obj.maskTexture,myrect,myrect);
					Screen('BlendFunction', w, obj.srcMode, obj.dstMode);
					Screen('gluDisk',w,[1 0 1],center(1),center(2),2);
					Screen('DrawingFinished', w); % Tell PTB that no  further drawing commands will follow before Screen('Flip')
					
					[~, ~, buttons]=GetMouse(0);
					if any(buttons) % break out of loop
						break;
					end;
					obj.xy=obj.xy+obj.dxdy;
					fix=find(obj.xy > ((obj.size*obj.ppd)/2));
					obj.xy(fix)=obj.xy(fix)-(obj.size*obj.ppd);
					fix=find(obj.xy < -(obj.size*obj.ppd)/2);
					obj.xy(fix)=obj.xy(fix)+(obj.size*obj.ppd);
					vbl=Screen('Flip', w);
				end
				
				obj.reset;
				Priority(0);
				Screen('CloseAll');
				
			catch ME
				obj.reset;
				Priority(0);
				Screen('CloseAll');
				rethrow(ME)
			end
		end
	end
	
	
	%---END PUBLIC METHODS---%
	
	methods ( Access = private ) %----------PRIVATE METHODS---------%
		% ===================================================================
		%> @brief sfOut Set method
		%>
		% ===================================================================
		function setcoherenceOut(obj,value)
			obj.coherenceOut = value;
			obj.updateDots;
		end
		
		% ===================================================================
		%> @brief sfOut Set method
		%>
		% ===================================================================
		function setangleOut(obj,value)
			obj.coherenceOut = value;
			obj.updateDots;
		end
		
		% ===================================================================
		%> @brief sfOut Set method
		%>
		% ===================================================================
		function setsizeOut(obj,value)
			obj.sizeOut = value * obj.ppd;
			if obj.mask == 1
				obj.fieldSize = obj.sizeOut * obj.fieldScale; %for masking!
			else
				obj.fieldSize = obj.sizeOut;
			end
		end
		
		% ===================================================================
		%> @brief sfOut Set method
		%>
		% ===================================================================
		function setdotSizeOut(obj,value)
			obj.dotSizeOut = value * obj.ppd;
		end
		
		% ===================================================================
		%> @brief xPositionOut Set method
		%>
		% ===================================================================
		function setxPositionOut(obj,value)
			obj.xPositionOut = obj.xCenter + (value * obj.ppd);
		end
		
		% ===================================================================
		%> @brief yPositionOut Set method
		%>
		% ===================================================================
		function setyPositionOut(obj,value)
			obj.yPositionOut = obj.yCenter + (value * obj.ppd);
		end
	end
end