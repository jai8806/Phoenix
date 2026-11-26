import '../models/user.dart';

/// Placeholder subject map used until the official precis is ingested.
/// The knowledge-base pipeline replaces this with subjects read from the
/// syllabus documents, so treat these names as provisional.
const commonSubjects = [
  'NCC General',
  'National Integration & Awareness',
  'Drill',
  'Weapon Training',
  'Personality Development',
  'Leadership',
  'Disaster Management',
  'Social Awareness & Community Development',
  'Health & Hygiene',
  'Environment Awareness',
  'Adventure',
];

const wingSubjects = <Wing, List<String>>{
  Wing.army: [
    'Armed Forces',
    'Map Reading',
    'Field Craft & Battle Craft',
    'Military History',
    'Communication',
  ],
  Wing.navy: [
    'Naval Orientation',
    'Naval Communication',
    'Navigation',
    'Seamanship',
    'Fire Fighting & Damage Control',
  ],
  Wing.air: [
    'General Service Knowledge',
    'Principles of Flight',
    'Airmanship',
    'Aircraft Recognition',
    'Aero Modelling',
  ],
  Wing.rvc: [
    'Animal Management',
    'Equitation',
    'Veterinary First Aid',
  ],
};
