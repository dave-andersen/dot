
#ifndef PLUGIN_H_
#define PLUGIN_H_

#include "amisc.h"

class Plugin {
    public:
        Plugin() { };
        virtual ~Plugin() { };
        virtual bool configure(str s, str pluginClass) = 0;
};

#endif /* PLUGIN_H_ */
