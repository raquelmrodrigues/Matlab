% This script was made by RODRIGUES, Raquel Mendes and was based on:
% https://topotoolbox.wordpress.com/2017/03/06/chimaps-in-a-few-lines-of-code-2/
% https://topotoolbox.wordpress.com/2017/10/24/bayesian-optimization-of-the-mn-ratio/
% https://topotoolbox.wordpress.com/2017/03/18/chimaps-in-a-few-lines-of-code-5/

addpath(genpath('C:\Users\Raquel\Documents\topotoolbox-master'))

%% 

Filename = 'mde_bh01.tif';
% The DEM must be in a projected coordinate system (preferably WGS84UTM)
% and the horizontal and vertical axis must have the same measurement unit
% (e.g meters).

DEMFillSink = 'nearest';
% Possible Options for DEMFillSink:
%
% - 'laplace': (default): laplace interpolation as implemented in roifill.
% - 'fill': elevate all values in each connected region of missing values 
%           to the minimum value of the surrounding pixels (same as the
%           function nibble in ArcGIS Spatial Analyst).
% - 'nearest': nearest neighbor interpolation using bwdist.
% - 'neighbors': this option does not close all nan-regions. It adds a
%                one-pixel wide boundary to the valid values in the DEM and
%                derives values for these pixels by a distance-weighted
%                average from the valid neighbor pixels. This approach does
%                not support the third input argument k.


FDPreprocess = 'carve';
% Possible Options for FDPreprocess:
% - carve
% - fill
%
% The preprocess option ‘carve’ works similarly to the ‘fill’ option. The
% difference, however, is that FLOWobj won’t seek the best path along the
% centerlines of flat sections. Instead it tries to find the path through
% sinks that runs along the deepest path, e.g. the valley bottom.

MiniArea = 1000;
BaseLevel = 245;

FracShareWithNaN = 1;
% The FracShareWithNaN variable is used to modify the STREAMobj so that it
% contains only streams where drainage basins share less than
% FracShareWithNaN% with the NaN mask.

A0 = 1e8;

Plot = 'y';
% Possible Options for Plot:
% - 'y': plot the results.
% - 'n': do not plot the results.

Seglength = 500;
% When converting the stream network to map struct the streamnetwork is 
% subdivided in reaches with approximate length in map units defined by the
% parameter value pair 'seglength'-length.

OutputFilename = 'chi_bh01.shp';

%%

% Load DEM
DEM = GRIDobj(Filename);

% Fill sink
DEM.Z(DEM.Z == -9999);
DEM = inpaintnans(DEM, DEMFillSink);

% Calculate flow direction
FD = FLOWobj(DEM,'preprocess',FDPreprocess);

% Calculate flow accumulation
A  = flowacc(FD);

% Create an instance of a stream object
S = STREAMobj(FD,'minarea', MiniArea);

% Create a new GRIDobj with river outlets
C = griddedcontour(DEM,[BaseLevel BaseLevel]);
C.Z = bwmorph(C.Z,'diag');

% Modify the stream network S to have only rivers up from the BaseLevel
S = modify(S,'upstreamto',C);

% Get drainage basins
D = drainagebasins(FD,S);
  
% Get NaN mask and dilate it by one pixel.
I = isnan(DEM);
I = dilate(I,ones(3));
 
% Add border pixels to the mask
%I.Z([1 end],:) = true;
%I.Z(:,[1 end]) = true;
  
% Get outlines for each basin
OUTLINES = false(DEM.size);
for r = 1:max(D)
    OUTLINES = OUTLINES | bwperim(D.Z == r);
end
  
% Calculate the fraction that each outline shares with the NaN mask
frac = accumarray(D.Z(OUTLINES),I.Z(OUTLINES),[],@mean);
  
% Grid the fractions
FRAC = GRIDobj(DEM);
FRAC.Z(:,:) = nan;
FRAC.Z(D.Z>0) = frac(D.Z(D.Z>0));

% Modify the STREAMobj so that it contains only streams where drainage
% basins share less than FracShareWithNaN with the NaN mask
S = modify(S,'upstreamto',FRAC<=FracShareWithNaN);

% Calculate the mnratio by Bayesian Optimization
[mn, ~] = mnoptim(S,DEM,A,'optvar','mn','crossval',true);

% Compute the Chi index
c = chitransform(S,A,'mn', mn.mn, 'a0', A0);

if Plot == 'y'
   figure;
   imageschs(DEM,[],'colormap', [1 1 1],...
                 'colorbar',false,...
                 'ticklabel', 'nice');
    hold on;
    plotc(S,c);
    colormap(jet);
    colorbar;
    hold off;
end

% Convert the Stream obj to map struct
MS = STREAMobj2mapstruct(S, 'seglength', Seglength, ...
                         'attributes',{'chi' c @mean});
% Export the map struct as a shapefile
shapewrite(MS, OutputFilename);
