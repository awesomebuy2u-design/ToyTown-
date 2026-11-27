import 'package:flutter/material.dart';

const toyTownVersion = '1.0.16';

void showToyTownVersion(BuildContext context) => showAboutDialog(
  context: context,
  useRootNavigator: false,
  applicationName: 'ToyTown',
  applicationVersion: '$toyTownVersion · збірка 26',
  applicationIcon: const Icon(Icons.toys, size: 40),
);
