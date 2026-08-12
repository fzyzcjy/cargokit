#include <string>

extern "C" unsigned int cargokit_cpp_runtime_probe() {
  return std::string("cargokit").size();
}
