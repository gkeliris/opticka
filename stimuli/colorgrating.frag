/*
 * File: colorgrating.frag
 * Shader for drawing of color gratings.
 *
 * Copyright 2014, Ian Andolina <http://github.com/iandol>, licenced under the MIT Licence
 *
 */

uniform float radius;
uniform vec2 center;
uniform vec4 color1;
uniform vec4 color2;

varying vec3 baseColor;
varying float alpha;
varying float phase;
varying float frequency;
varying float sigma;
varying float contrast;

void main() {
	//current position
	vec2 pos = gl_TexCoord[0].xy;

	/* find our distance from center, if distance to center (aka radius of pixel) > Radius, discard this pixel: */
	if (radius > 0.0) {
		float dist = distance(pos, center);
		if (dist > radius) discard;
	}

	//create our sinusoid in -1 to 1 range
	float sv = sin(pos.x * frequency + phase);

	//if sigma >= 0, we want a squarewave grating, step or smoothstep does this depending on sigma value
	if (sigma == 0.0) {
		sv = step(sigma, sv); //converts into 0-1 range
	}
	else if (sigma > 0.0) {
		sv = smoothstep(-sigma, sigma, sv); //converts into 0-1 range
	}
	else {
		sv = (sv + 1.0) / 2.0; //simply get sv into 0 - 1 range (preserving sinusoid);
	}

	vec3 colorA = color1.rgb;
	vec3 colorB = color2.rgb;
	if (contrast < 1.0) { //blend our colours from base colour if contrast < 1
		colorA = mix(baseColor, color1.rgb, contrast);
		colorB = mix(baseColor, color2.rgb, contrast);
	}

	// and then mix our two colors using sv (our position in the grating)
	vec3 colorOut = mix(colorA, colorB, sv);
	
	// off to the display, byebye little pixel!
	gl_FragColor = vec4(colorOut,alpha);
}