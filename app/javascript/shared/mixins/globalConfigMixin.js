export const useInstallationName = (str, installationName) => {
  if (str && installationName) {
    return str.replace(/NeuChat/g, installationName);
  }
  return str;
};

export default {
  methods: {
    useInstallationName,
  },
};
